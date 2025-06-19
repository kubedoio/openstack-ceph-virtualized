#!/usr/bin/env bash
#
# deploy_openstack.sh  – run on the Proxmox host
#   • copies the shared config to os0 (jump host)
#   • pushes & runs a self-contained OpenStack deployer there
#
set -euo pipefail

### --------------------------------------------------------------------------
### 0. Load shared configuration ---------------------------------------------
### --------------------------------------------------------------------------
CONFIG_FILE="$(dirname "$0")/rook_ceph.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "   $CONFIG_FILE missing – run from the directory that holds the config."
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

OS0_IP="${BASE_IP}.${START_IP_SUFFIX}"          # jump host address
REMOTE_SCRIPT="/home/ubuntu/openstack-deploy.sh"

### --------------------------------------------------------------------------
### 1.  Build the *remote* deployer script  ----------------------------------
### --------------------------------------------------------------------------
cat > /tmp/openstack-deploy.sh <<'REMOTE_EOF'
#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Load the same central config on the jump host --------------------------
# ---------------------------------------------------------------------------
CONFIG_FILE="/home/ubuntu/rook_ceph.conf"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

export KUBECONFIG=/home/ubuntu/.kube/config
export ANSIBLE_HOST_KEY_CHECKING=False

# ---------------------------------------------------------------------------
# 1. Install kolla-ansible into a venv --------------------------------------
# ---------------------------------------------------------------------------
sudo apt-get update
sudo apt-get install -y python3-virtualenv git

mkdir -p "$KOLLA_DIR"
cd "$KOLLA_DIR"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install git+https://opendev.org/openstack/kolla-ansible@master

# Copy example inventory & install deps
cp .venv/share/kolla-ansible/ansible/inventory/"${OPENSTACK_INVENTORY_FILE}" .
kolla-ansible install-deps

# ---------------------------------------------------------------------------
# 2. Prepare /etc/kolla and passwords ---------------------------------------
# ---------------------------------------------------------------------------
sudo mkdir -p /etc/kolla/config /etc/ceph
sudo chown -R "$(whoami):$(whoami)" /etc/kolla /etc/ceph
cp -r .venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
kolla-genpwd

# ---------------------------------------------------------------------------
# 3. Build the multinode inventory from $OPENSTACK_NODE_LIST ----------------
# ---------------------------------------------------------------------------
INV="${OPENSTACK_INVENTORY_FILE}"
# wipe existing host lists
awk '
  BEGIN {skip=0}
  /^\[.*\]/          {skip=0}
  /^\[(control|compute|network|monitoring|storage)\]/ {print; skip=1; next}
  skip==1 && /^[^[]/ {next}
  {print}
' "$INV" > "${INV}.tmp" && mv "${INV}.tmp" "$INV"

{
  for SECTION in control compute network monitoring storage; do
    echo "[$SECTION]"
    for node in "${OPENSTACK_NODE_LIST[@]}"; do
      IFS=":" read -r NAME IP <<< "\$node"
      echo "\$NAME ansible_host=\$IP ansible_user=ubuntu"
    done
    echo
  done
} >> "$INV"

# ---------------------------------------------------------------------------
# 4. Write /etc/kolla/globals.yml from config vars --------------------------
# ---------------------------------------------------------------------------
cat > /etc/kolla/globals.yml <<EOF
---
workaround_ansible_issue_8743: yes
kolla_base_distro: ubuntu
kolla_internal_vip_address: "${KOLLA_INTERNAL_VIP_ADDRESS}"
kolla_external_vip_interface: "${KOLLA_EXTERNAL_VIP_INTERFACE}"
network_interface: "${NETWORK_INTERFACE}"
neutron_external_interface: "${NEUTRON_EXTERNAL_INTERFACE}"
neutron_plugin_agent: "${NEUTRON_PLUGIN_AGENT}"
enable_neutron_dvr: "${ENABLE_NEUTRON_DVR}"
multiple_regions_names: ["{{ openstack_region_name }}"]

enable_openstack_core: "yes"
enable_hacluster: "yes"
enable_cinder: "yes"
enable_cinder_backup: "yes"
enable_horizon: "yes"
enable_keystone: "yes"
openstack_region_name: "RegionOne"
enable_horizon_neutron_vpnaas: "yes"
enable_masakari: "yes"
enable_masakari_instancemonitor: "yes"
enable_masakari_hostmonitor: "yes"
enable_neutron_vpnaas: "yes"
enable_neutron_provider_networks: "yes"

external_ceph_cephx_enabled: "yes"
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"
ceph_cinder_user: "cinder"
ceph_cinder_keyring: "ceph.client.cinder.keyring"
ceph_cinder_pool_name: "volumes"
cinder_backend_ceph: "yes"
cinder_backup_driver: "ceph"
EOF

# ---------------------------------------------------------------------------
# 5. Prepare Ceph pools + keyrings via rook-ceph-tools -----------------------
# ---------------------------------------------------------------------------
TOOLS_POD=$(kubectl -n rook-ceph get pods -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')

for pool in "${CEPH_POOLS[@]}"; do
  echo "ensuring Ceph pool $pool exists"
  kubectl -n rook-ceph exec $TOOLS_POD -- ceph osd pool ls | grep -q "^\\$pool\$" \
    || kubectl -n rook-ceph exec $TOOLS_POD -- ceph osd pool create $pool
  kubectl -n rook-ceph exec $TOOLS_POD -- rbd pool init $pool || true
done

kubectl -n rook-ceph exec $TOOLS_POD -- ceph config generate-minimal-conf > /etc/ceph/ceph.conf
echo -e "auth_cluster_required = cephx\nauth_service_required = cephx\nauth_client_required = cephx" >> /etc/ceph/ceph.conf

# ---------------------------------------------------------------------------
# 6. Create keyrings for Glance, Cinder & Nova ------------------------------
# ---------------------------------------------------------------------------
declare -A KEYRINGS=(
  [glance]="mon 'profile rbd' osd 'profile rbd pool=images' mgr 'profile rbd pool=images'"
  [cinder]="mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes, profile rbd pool=vms'"
  [cinder-backup]="mon 'profile rbd' osd 'profile rbd pool=backups' mgr 'profile rbd pool=backups'"
)

for user in "${!KEYRINGS[@]}"; do
  path="/etc/kolla/config/${user%%-*}/ceph.client.$user.keyring"
  mkdir -p "$(dirname "$path")"
  kubectl -n rook-ceph exec $TOOLS_POD -- \
    ceph auth get-or-create client.$user ${KEYRINGS[$user]} > "$path"
  cp /etc/ceph/ceph.conf "$(dirname "$path")/ceph.conf"
done

# nova-compute needs the uuid from passwords.yml
mkdir -p /etc/kolla/config/nova
cp -rp /etc/kolla/config/cinder/* /etc/kolla/config/nova/

echo "[libvirt]" >> /etc/kolla/config/nova/nova-compute.conf
grep '^rbd_secret_uuid' /etc/kolla/passwords.yml | sed 's/:/ =/' >> /etc/kolla/config/nova/nova-compute.conf

# ---------------------------------------------------------------------------
# 7. Bootstrap servers & deploy OpenStack -----------------------------------
# ---------------------------------------------------------------------------
kolla-ansible bootstrap-servers -i "$INV"
kolla-ansible deploy             -i "$INV"

echo
echo "   Kolla-Ansible finished.  Run the post-deploy steps manually:"
echo "    kolla-ansible post-deploy -i $INV"
echo "    source /etc/kolla/admin-openrc.sh"
echo "    ./init-runonce   # (after editing it to your network)"
REMOTE_EOF
chmod +x /tmp/openstack-deploy.sh

### --------------------------------------------------------------------------
### 2.  Ship config + deployer to os0 & execute ------------------------------
### --------------------------------------------------------------------------
echo "Copying config and deployer to os0 (${OS0_IP})…"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$CONFIG_FILE" ubuntu@"$OS0_IP":/home/ubuntu/rook_ceph.conf
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    /tmp/openstack-deploy.sh ubuntu@"$OS0_IP":"$REMOTE_SCRIPT"

echo "🚀  Running OpenStack deployer on os0… (this will take a while)"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@"$OS0_IP" \
    "chmod +x '$REMOTE_SCRIPT' && bash '$REMOTE_SCRIPT'"
