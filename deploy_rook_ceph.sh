#!/usr/bin/env bash
#
# deploy_rook_ceph.sh
#   – Runs *inside* a Proxmox node.
#   – Creates VMs, installs Kubernetes with Kubespray,
#     and deploys Rook-Ceph.
#   – All user-changeable values live in rook_ceph.conf.
#

set -euo pipefail

### --------------------------------------------------------------------------
### 0. Load configuration  ---------------------------------------------------
### --------------------------------------------------------------------------
CONFIG_FILE="$(dirname "$0")/rook_ceph.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Configuration file $CONFIG_FILE not found. Aborting."
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

### Derived values
OS_LAST_ID=$((OS0_ID + NODE_COUNT))                        # highest VM-ID used
NODE_LIST=()                                               # os0 … osN IPs
for i in $(seq 0 "$NODE_COUNT"); do
  NODE_LIST+=( "$BASE_IP.$((START_IP_SUFFIX + i))" )
done

echo "    Using config from $CONFIG_FILE"
echo "    Jump host VM-ID : $OS0_ID  (${NODE_LIST[0]})"
echo "    Worker VMs      : $NODE_COUNT  (IDs $(($OS0_ID+1))-$OS_LAST_ID)"
echo "    Template ID     : $TEMPLATE_ID"
echo "    Gateway         : $GATEWAY"
echo

### --------------------------------------------------------------------------
### 1. Create & initialise os0  ----------------------------------------------
### --------------------------------------------------------------------------
echo "Creating jump host (os0)…"
./create-vm.sh "$TEMPLATE_ID" "$OS0_ID" \
               "${VM_PREFIX}0.cluster.local" \
               "${NODE_LIST[0]}/24" "$GATEWAY"

qm start "$OS0_ID"
sleep 20    # give cloud-init SSH time to appear

echo "Generating SSH key on os0 and collecting it locally…"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@"${NODE_LIST[0]}" \
    'ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1'
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@"${NODE_LIST[0]}" \
    'cat ~/.ssh/id_rsa.pub' >> "$PUB_KEY_FILE"

### --------------------------------------------------------------------------
### 2. Create remaining VMs  -------------------------------------------------
### --------------------------------------------------------------------------
echo "Creating worker VMs (os1…os${NODE_COUNT})…"
for i in $(seq 1 "$NODE_COUNT"); do
  VM_ID=$((OS0_ID + i))
  IP_SUFFIX=$((START_IP_SUFFIX + i))
  HOSTNAME="${VM_PREFIX}${i}.cluster.local"
  IP="$BASE_IP.$IP_SUFFIX"
  ./create-vm.sh "$TEMPLATE_ID" "$VM_ID" "$HOSTNAME" "$IP/24" "$GATEWAY"
done

### --------------------------------------------------------------------------
### 3. Bump RAM on designated OpenStack nodes  -------------------------------
### --------------------------------------------------------------------------
for idx in "${OPENSTACK_NODE_INDEXES[@]}"; do
  VM_ID=$((OS0_ID + idx))
  echo "Setting ${VM_PREFIX}${idx} (VM-ID $VM_ID) memory to ${OPENSTACK_MEMORY_MB} MiB"
  qm set "$VM_ID" --memory "$OPENSTACK_MEMORY_MB"
done

### --------------------------------------------------------------------------
### 4. Boot all VMs  ---------------------------------------------------------
### --------------------------------------------------------------------------
echo "Booting all worker VMs…"
for i in $(seq 1 "$NODE_COUNT"); do
  qm start $((OS0_ID + i))
done

### --------------------------------------------------------------------------
### 5. Prepare & run the remote deployer
### since we use cloudinit-ubuntu image default directory is /home/ubuntu
### --------------------------------------------------------------------------
REMOTE_SCRIPT_PATH="/home/ubuntu/rook-ceph-deploy.sh"
REMOTE_CONFIG_PATH="/home/ubuntu/rook_ceph.conf"

echo "Copying config & deployer to os0…"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$CONFIG_FILE" ubuntu@"${NODE_LIST[0]}":"$REMOTE_CONFIG_PATH"

# Build the remote script locally and then copy it over
cat > /tmp/rook-ceph-deploy.sh <<'REMOTE_EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/home/ubuntu/rook_ceph.conf"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

echo "Installing kubectl, Git, Python tooling…"
sudo apt update
sudo apt install -y git python3-venv python3-pip jq curl

# ---------------------------------------------------------------------------
# 1. kubectl get the latest stable kubectl and install k9s (very handy)
# ---------------------------------------------------------------------------
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin

wget https://github.com/derailed/k9s/releases/download/v0.50.6/k9s_linux_amd64.deb
sudo dpkg -i k9s_linux_amd64.deb

# ---------------------------------------------------------------------------
# 2. Kubespray
# ---------------------------------------------------------------------------
if [[ ! -d "$KUBESPRAY_DIR" ]]; then
  git clone https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
fi

cd "$KUBESPRAY_DIR"
python3 -m venv .venv
source .venv/bin/activate
pip install -U -r requirements.txt --break-system-packages

cp -rfp inventory/sample "inventory/${INVENTORY_NAME}"

# Build hosts.yaml from the same config values ------------------------------
cat > "inventory/${INVENTORY_NAME}/hosts.yaml" <<EOF
all:
  hosts:
EOF

for i in $(seq 1 4); do
  IP="$BASE_IP.$((START_IP_SUFFIX + i))"
  NAME="${VM_PREFIX}${i}"
  cat >> "inventory/${INVENTORY_NAME}/hosts.yaml" <<EOF
    ${NAME}:
      ansible_host: ${IP}
      ip: ${IP}
      access_ip: ${IP}
EOF
done

cat >> "inventory/${INVENTORY_NAME}/hosts.yaml" <<EOF

  children:
    kube_control_plane:
      hosts:
        ${VM_PREFIX}1:

    kube_node:
      hosts:
EOF

for i in $(seq 1 4); do
  echo "        ${VM_PREFIX}${i}:" >> "inventory/${INVENTORY_NAME}/hosts.yaml"
done

cat >> "inventory/${INVENTORY_NAME}/hosts.yaml" <<EOF

    etcd:
      hosts:
        ${VM_PREFIX}1:

    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:

    calico_rr:
      hosts: {}
EOF

echo "kubeconfig_localhost: true" >> "inventory/${INVENTORY_NAME}/group_vars/k8s_cluster/k8s-cluster.yml"

echo "Running Kubespray playbook…"
ansible-playbook -i "inventory/${INVENTORY_NAME}/hosts.yaml" \
                 --become --become-user=root -u ubuntu cluster.yml

# ---------------------------------------------------------------------------
# 3. Fetch Kubeconfig and install Rook-Ceph
# ---------------------------------------------------------------------------
sleep 20
echo "Deploying Rook-Ceph…"
cd ~
mkdir -p ~/.kube
ssh -o StrictHostKeyChecking=no ubuntu@"$BASE_IP.$((START_IP_SUFFIX+1))" \
    'sudo cat /etc/kubernetes/admin.conf' \
    | sed "s/127.0.0.1/$BASE_IP.$((START_IP_SUFFIX+1))/g" > ~/.kube/config

git clone https://github.com/rook/rook.git
cd rook/deploy/examples

sed -i '/^  network:/a\    hostNetwork: true' cluster.yaml
kubectl apply -f crds.yaml -f common.yaml -f operator.yaml

echo "Waiting for rook-ceph-operator to be ready…"
kubectl -n rook-ceph rollout status deploy/rook-ceph-operator --timeout=180s

kubectl apply -f cluster.yaml -f toolbox.yaml -f dashboard-external-http.yaml

echo
echo "Rook-Ceph installation kicked off!"
echo "Watch progress with:  kubectl -n rook-ceph get pods -w"
REMOTE_EOF

chmod +x /tmp/rook-ceph-deploy.sh
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    /tmp/rook-ceph-deploy.sh ubuntu@"${NODE_LIST[0]}":"$REMOTE_SCRIPT_PATH"

echo " Executing remote deployer on os0…"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@"${NODE_LIST[0]}" \
    "chmod +x '$REMOTE_SCRIPT_PATH' && bash '$REMOTE_SCRIPT_PATH'"