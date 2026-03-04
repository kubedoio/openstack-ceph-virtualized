# Configuration Reference

This document provides detailed information about all configuration files and parameters.

---

## Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `rook_ceph.conf` | **Primary configuration file** - all deployment settings | Project root |
| `pub_keys` | SSH public keys for VM access | Project root |
| `globals.yml` | OpenStack service configuration (generated) | `/etc/kolla/globals.yml` on os0 |
| `passwords.yml` | OpenStack passwords (auto-generated) | `/etc/kolla/passwords.yml` on os0 |
| `hosts.yaml` | Kubernetes cluster inventory (generated) | `~/kubespray/inventory/<name>/hosts.yaml` on os0 |
| `multinode` | OpenStack inventory (modified) | `~/kolla/multinode` on os0 |

---

## Primary Configuration: `rook_ceph.conf`

This is the **single source of truth** for the entire deployment. All scripts source this file.

### Network Configuration

```bash
### Network Settings ###

# Gateway for all VMs
GATEWAY="10.1.199.254"

# Base IP (first three octets) - VMs will be assigned IPs in this subnet
BASE_IP="10.1.199"

# Starting IP suffix - os0 (jump host) will get BASE_IP.START_IP_SUFFIX
# Subsequent VMs get incremental IPs
START_IP_SUFFIX=140
```

**Example**: With `BASE_IP="10.1.199"` and `START_IP_SUFFIX=140`:
- os0: `10.1.199.140`
- os1: `10.1.199.141`
- os2: `10.1.199.142`
- etc.

**To change IP range**:
```bash
BASE_IP="192.168.100"
START_IP_SUFFIX=50
GATEWAY="192.168.100.1"
```
This would assign:
- os0: `192.168.100.50`
- os1: `192.168.100.51`
- etc.

---

### Proxmox/VM Configuration

```bash
### Proxmox Settings ###

# VM template ID for cloud-init Ubuntu image
# Must be created first with cloud-init-template.sh
TEMPLATE_ID=4444

# Jump host (os0) VM ID
OS0_ID=4140

# Total number of worker VMs (os1, os2, ..., os<NODE_COUNT>)
NODE_COUNT=6

# Hostname prefix for VMs
VM_PREFIX="os"
```

**Derived values**:
- Jump host: `${VM_PREFIX}0` → `os0`
- Workers: `${VM_PREFIX}1` through `${VM_PREFIX}${NODE_COUNT}` → `os1` to `os6`
- VM IDs: `$OS0_ID` for os0, then `$OS0_ID+1`, `$OS0_ID+2`, etc.

**To create 10 VMs total (os0-os9)**:
```bash
NODE_COUNT=9  # os1 through os9
OS0_ID=5000   # os0 will be VM 5000, os1=5001, etc.
```

---

### OpenStack-Specific Configuration

```bash
### OpenStack Node Resources ###

# Which VMs in the cluster get extra RAM for OpenStack
# These are INDEXES, not VM IDs!
# Index 5 = os5 (6th VM), Index 6 = os6 (7th VM)
OPENSTACK_NODE_INDEXES=(5 6)

# RAM allocation for OpenStack nodes (in MB)
OPENSTACK_MEMORY_MB=32768  # 32GB
```

**Example**: To make os7, os8, os9 OpenStack nodes with 64GB RAM:
```bash
NODE_COUNT=9
OPENSTACK_NODE_INDEXES=(7 8 9)
OPENSTACK_MEMORY_MB=65536
```

**Note**: Default RAM for all VMs is 8GB (set in `create-vm.sh`). OpenStack nodes get upgraded to `OPENSTACK_MEMORY_MB`.

---

### Kubernetes Configuration

```bash
### Kubernetes / Kubespray Settings ###

# Directory where Kubespray will be cloned on os0
KUBESPRAY_DIR="kubespray"

# Name for the Kubespray inventory
INVENTORY_NAME="rook-ceph-k8s"
```

**Generated files on os0**:
- Kubespray repo: `~/${KUBESPRAY_DIR}/`
- Inventory: `~/${KUBESPRAY_DIR}/inventory/${INVENTORY_NAME}/hosts.yaml`
- Virtualenv: `~/${KUBESPRAY_DIR}/.venv/`

---

### OpenStack/Kolla Configuration

```bash
### OpenStack / Kolla-Ansible Settings ###

# Directory where Kolla-Ansible will be installed on os0
KOLLA_DIR="kolla"

# Inventory file name (from Kolla examples)
OPENSTACK_INVENTORY_FILE="multinode"

# List of OpenStack nodes (name:IP format)
# Add or remove entries as needed
OPENSTACK_NODE_LIST=(
  "os5:10.1.199.145"
  "os6:10.1.199.146"
)
```

**To add a third OpenStack node**:
```bash
NODE_COUNT=7  # Need os7 to exist
OPENSTACK_NODE_INDEXES=(5 6 7)
OPENSTACK_NODE_LIST=(
  "os5:10.1.199.145"
  "os6:10.1.199.146"
  "os7:10.1.199.147"
)
```

---

### Kolla globals.yml Tunables

These values are written to `/etc/kolla/globals.yml` on os0:

```bash
### Kolla globals.yml Configuration ###

# Virtual IP for OpenStack API endpoints (HA/failover)
KOLLA_INTERNAL_VIP_ADDRESS="10.1.199.150"

# External network interface (for floating IPs, provider networks)
# Maps to Proxmox bridge vmbr2199
KOLLA_EXTERNAL_VIP_INTERFACE="ens19"

# Internal management interface (for API communication)
# Maps to Proxmox bridge vmbr1199
NETWORK_INTERFACE="eth0"

# Neutron external interface (VMs get floating IPs via this)
NEUTRON_EXTERNAL_INTERFACE="ens19"

# Neutron plugin (openvswitch or linuxbridge)
NEUTRON_PLUGIN_AGENT="openvswitch"

# Enable Distributed Virtual Router (DVR)
ENABLE_NEUTRON_DVR="yes"
```

**Interface Mapping**:
```
Proxmox Bridge  →  VM Interface  →  Kolla Variable
─────────────────────────────────────────────────
vmbr1199        →  eth0          →  NETWORK_INTERFACE
vmbr2199        →  ens19         →  NEUTRON_EXTERNAL_INTERFACE
```

**To use different interface names**:
```bash
NETWORK_INTERFACE="enp1s0"
NEUTRON_EXTERNAL_INTERFACE="enp2s0"
```

---

### Ceph Pool Configuration

```bash
### Ceph Storage Pools ###

# Pools created in Rook-Ceph for OpenStack services
CEPH_POOLS=(volumes images backups vms)
```

**Pool usage**:
- `volumes`: Cinder persistent volumes
- `images`: Glance VM images
- `backups`: Cinder volume backups
- `vms`: Nova ephemeral instance storage

**To add additional pools** (e.g., for Swift/RGW):
```bash
CEPH_POOLS=(volumes images backups vms rgw-data)
```

---

### Miscellaneous Settings

```bash
### Miscellaneous ###

# File containing SSH public keys
PUB_KEY_FILE="pub_keys"
```

**Usage**: This file is injected into VMs via Proxmox `qm set --sshkey`.

---

## SSH Key Configuration: `pub_keys`

### Format

Plain text file, one SSH public key per line:

```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@hostname
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@hostname
```

### Creating Keys

```bash
# Generate new key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy to pub_keys
cat ~/.ssh/id_ed25519.pub > pub_keys

# Add additional keys
cat ~/.ssh/id_rsa.pub >> pub_keys
```

### Security Note

⚠️ This file contains **public** keys only - safe to commit to git.
❌ Never commit private keys (`id_rsa`, `id_ed25519`, etc.)!

---

## Kubespray Configuration

### Generated Inventory

Location: `~/kubespray/inventory/${INVENTORY_NAME}/hosts.yaml` on os0

**Structure**:
```yaml
all:
  hosts:
    os1:
      ansible_host: 10.1.199.141
      ip: 10.1.199.141
      access_ip: 10.1.199.141
    os2:
      ansible_host: 10.1.199.142
      ip: 10.1.199.142
      access_ip: 10.1.199.142
    # ... os3, os4 ...

  children:
    kube_control_plane:
      hosts:
        os1:  # Single control plane

    kube_node:
      hosts:
        os1:  # os1 is also a worker
        os2:
        os3:
        os4:

    etcd:
      hosts:
        os1:  # Single etcd node

    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:

    calico_rr:
      hosts: {}
```

### Kubespray Customization

Location: `~/kubespray/inventory/${INVENTORY_NAME}/group_vars/k8s_cluster/k8s-cluster.yml`

**Default additions**:
```yaml
kubeconfig_localhost: true  # Copy kubeconfig to os0
```

**Common customizations**:
```yaml
# Change Kubernetes version
kube_version: v1.29.0

# Change pod subnet
kube_pods_subnet: 10.244.0.0/16

# Change service subnet
kube_service_addresses: 10.96.0.0/12

# Enable metrics server
metrics_server_enabled: true

# Enable ingress
ingress_nginx_enabled: true
```

**To customize**: Edit the file on os0 after Kubespray is cloned but before running the playbook.

---

## Kolla-Ansible Configuration

### Generated globals.yml

Location: `/etc/kolla/globals.yml` on os0

**Key sections**:

```yaml
---
# Base settings
workaround_ansible_issue_8743: yes
kolla_base_distro: "ubuntu"
kolla_internal_vip_address: "10.1.199.150"

# Network
network_interface: "eth0"
neutron_external_interface: "ens19"
kolla_external_vip_interface: "ens19"
neutron_plugin_agent: "openvswitch"
enable_neutron_dvr: "yes"

# Core services
enable_openstack_core: "yes"
enable_hacluster: "yes"
enable_horizon: "yes"
enable_keystone: "yes"

# Storage services
enable_cinder: "yes"
enable_cinder_backup: "yes"
cinder_backend_ceph: "yes"
glance_backend_ceph: "yes"

# Advanced services
enable_masakari: "yes"
enable_neutron_vpnaas: "yes"
enable_neutron_provider_networks: "yes"

# Ceph integration
external_ceph_cephx_enabled: "yes"
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"
ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"
# ... (more Ceph settings)
```

### Disabling Services

To reduce resource usage, disable optional services:

```yaml
# Disable telemetry
enable_ceilometer: "no"
enable_gnocchi: "no"

# Disable orchestration
enable_heat: "no"

# Disable object storage
enable_swift: "no"

# Disable Masakari (HA)
enable_masakari: "no"
```

**Location to edit**: `/etc/kolla/globals.yml` on os0 before running `kolla-ansible deploy`.

---

### Generated passwords.yml

Location: `/etc/kolla/passwords.yml` on os0

Auto-generated by `kolla-genpwd` with random passwords for all services.

**Key passwords**:
```bash
# Admin password for Horizon and OpenStack CLI
grep keystone_admin_password /etc/kolla/passwords.yml

# Database passwords
grep database_password /etc/kolla/passwords.yml

# RabbitMQ password
grep rabbitmq_password /etc/kolla/passwords.yml

# Ceph UUID for Nova
grep rbd_secret_uuid /etc/kolla/passwords.yml
```

**To regenerate**:
```bash
cd ~/kolla
source .venv/bin/activate
kolla-genpwd  # Regenerates all passwords
```

⚠️ **Warning**: Regenerating passwords after deployment will break the cluster!

---

### Kolla Inventory

Location: `~/kolla/multinode` on os0

**Relevant sections**:
```ini
[control]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu

[compute]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu

[network]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu

[monitoring]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu

[storage]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu
```

**Node role mapping**:
- `[control]`: Controller services (APIs, schedulers)
- `[compute]`: Nova compute nodes (hypervisors)
- `[network]`: Neutron networking (L3, DHCP agents)
- `[storage]`: Cinder volume service
- `[monitoring]`: Monitoring services (if enabled)

**Common topology changes**:

1. **Dedicated controllers**:
```ini
[control]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
os6 ansible_host=10.1.199.146 ansible_user=ubuntu

[compute]
os7 ansible_host=10.1.199.147 ansible_user=ubuntu
os8 ansible_host=10.1.199.148 ansible_user=ubuntu
```

2. **Single all-in-one**:
```ini
[control]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu

[compute]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu

[network]
os5 ansible_host=10.1.199.145 ansible_user=ubuntu
```

---

## Rook-Ceph Configuration

### Cluster YAML

Location: `~/rook/deploy/examples/cluster.yaml` on os0

**Key modifications made by scripts**:
```yaml
spec:
  network:
    hostNetwork: true  # Added by deploy script (line 199 in deploy_rook_ceph.sh)
```

**Common customizations**:

```yaml
# Change OSD count per node
storage:
  useAllNodes: true
  useAllDevices: false
  deviceFilter: "^sd[bc]$"  # Only use sdb and sdc

# Set replica size
cephBlockPools:
  - name: replicapool
    spec:
      replicated:
        size: 2  # Changed from 3 for smaller clusters
```

**To customize**: Edit `~/rook/deploy/examples/cluster.yaml` on os0 before applying.

---

### Ceph Configuration File

Location: `/etc/ceph/ceph.conf` on os0 (copied to OpenStack nodes)

**Generated content**:
```ini
[global]
fsid = <cluster-id>
mon_host = 10.1.199.141:6789,10.1.199.142:6789,10.1.199.143:6789

auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx
```

**Copied to**:
- `/etc/kolla/config/glance/ceph.conf`
- `/etc/kolla/config/cinder/ceph.conf`
- `/etc/kolla/config/nova/ceph.conf`

---

### Ceph Keyrings

Locations on os0:
- `/etc/kolla/config/glance/ceph.client.glance.keyring`
- `/etc/kolla/config/cinder/ceph.client.cinder.keyring`
- `/etc/kolla/config/cinder-backup/ceph.client.cinder-backup.keyring`

**Format**:
```ini
[client.glance]
    key = AQC...==
    caps mgr = "profile rbd pool=images"
    caps mon = "profile rbd"
    caps osd = "profile rbd pool=images"
```

---

## Cloud-Init Configuration

Applied to VMs via `qm set --ipconfig0`:

```bash
qm set $VM_ID --ipconfig0 ip=${IP}/24,gw=$GATEWAY
```

**Resulting cloud-init on VM**:
```yaml
#cloud-config
hostname: os1.cluster.local
fqdn: os1.cluster.local
manage_etc_hosts: true

# Network config (derived from ipconfig0)
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.1.199.141/24
      gateway4: 10.1.199.254
      nameservers:
        addresses:
          - 8.8.8.8

# SSH keys (from pub_keys file)
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1...
```

---

## Environment Variables

Set by scripts during deployment:

### On os0 (Jump Host)

```bash
# Kubeconfig location
export KUBECONFIG=/home/ubuntu/.kube/config

# Disable Ansible host key checking
export ANSIBLE_HOST_KEY_CHECKING=False
```

### In Kolla Deployment

```bash
# OpenStack admin credentials
source /etc/kolla/admin-openrc.sh

# This sets:
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=<from passwords.yml>
export OS_AUTH_URL=http://10.1.199.150:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne
export OS_INTERFACE=internal
```

---

## Configuration Validation

### Pre-Deployment Checks

```bash
# Check network bridges exist on Proxmox host
ip link show vmbr1199
ip link show vmbr2199

# Verify template exists
qm list | grep 4444

# Validate config file syntax
bash -n rook_ceph.conf  # Should return no errors

# Check SSH keys exist
test -s pub_keys && echo "OK" || echo "Empty!"
```

### Post-Deployment Checks

```bash
# Verify Kubernetes config
ssh ubuntu@10.1.199.140 'kubectl get nodes'

# Verify Ceph config
ssh ubuntu@10.1.199.140 'kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s'

# Verify OpenStack config
ssh ubuntu@10.1.199.140 'source /etc/kolla/admin-openrc.sh && openstack service list'
```

---

## Troubleshooting Configuration Issues

### Issue: Wrong IP addresses assigned

**Cause**: `BASE_IP` or `START_IP_SUFFIX` misconfigured.

**Fix**:
```bash
# Edit rook_ceph.conf
vim rook_ceph.conf

# Destroy and recreate VMs
qm destroy 4140 4141 4142 4143 4144 4145 4146
./deploy_rook_ceph.sh
```

### Issue: VMs can't reach gateway

**Cause**: Gateway unreachable or bridge misconfigured.

**Fix**:
```bash
# On Proxmox host, test gateway
ping 10.1.199.254

# Check bridge config
cat /etc/network/interfaces | grep -A 10 vmbr1199

# Verify VM can see bridge
ssh ubuntu@10.1.199.140
ip route show default
ping 10.1.199.254
```

### Issue: Kubespray fails with SSH errors

**Cause**: `pub_keys` file empty or invalid.

**Fix**:
```bash
# Regenerate pub_keys
cat ~/.ssh/id_rsa.pub > pub_keys

# Test SSH access
ssh ubuntu@10.1.199.141 'echo OK'
```

### Issue: OpenStack services won't start

**Cause**: Ceph credentials missing or invalid.

**Fix**:
```bash
# On os0, verify keyrings exist
ls -la /etc/kolla/config/*/ceph.client.*.keyring

# Test Ceph connectivity from OpenStack node
ssh ubuntu@10.1.199.145
ceph -s -c /etc/kolla/config/cinder/ceph.conf --keyring /etc/kolla/config/cinder/ceph.client.cinder.keyring
```

---

## Configuration Best Practices

1. **Version Control**: Commit `rook_ceph.conf` and `pub_keys` to git (public keys only!)
2. **Backup Configs**: Save generated files from os0 before major changes
3. **Document Changes**: Add comments to `rook_ceph.conf` explaining customizations
4. **Test Incrementally**: Validate each configuration section before proceeding
5. **Use Variables**: Avoid hardcoding IPs in scripts - use config file values
6. **Idempotency**: Design configs to be reapplied without breaking existing setup

---

## Configuration Templates

### Minimal Lab Setup (3 VMs)

```bash
# Minimal K8s cluster, no OpenStack
NODE_COUNT=2  # os1, os2 (2 K8s workers)
OPENSTACK_NODE_INDEXES=()  # No OpenStack nodes
OPENSTACK_NODE_LIST=()
```

### Small Production-Like Setup (10 VMs)

```bash
# 4 K8s, 3 dedicated OpenStack controllers, 3 compute
NODE_COUNT=9
OPENSTACK_NODE_INDEXES=(5 6 7 8 9)
OPENSTACK_NODE_LIST=(
  "os5:10.1.199.145"  # Controller
  "os6:10.1.199.146"  # Controller
  "os7:10.1.199.147"  # Controller
  "os8:10.1.199.148"  # Compute
  "os9:10.1.199.149"  # Compute
)
```

### High-Memory Setup (for large instances)

```bash
# 64GB RAM for OpenStack nodes
OPENSTACK_MEMORY_MB=65536
OPENSTACK_NODE_INDEXES=(5 6)
```

---

## Reference Documentation

For more details on underlying tools:
- Kubespray: https://kubespray.io/
- Kolla-Ansible: https://docs.openstack.org/kolla-ansible/latest/
- Rook-Ceph: https://rook.io/docs/rook/latest/
- Proxmox VE: https://pve.proxmox.com/pve-docs/
