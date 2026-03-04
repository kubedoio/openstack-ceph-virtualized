# Installation Guide

This guide walks you through deploying the complete virtualized OpenStack + Rook-Ceph environment.

---

## Prerequisites

### 1. Proxmox VE Setup

Ensure your Proxmox host has:
- Proxmox VE 7.x or 8.x installed
- Minimum 64GB RAM (128GB recommended)
- Network bridges configured:
  ```bash
  # Check existing bridges
  ip link show | grep vmbr

  # Required bridges:
  # vmbr1199 - Internal VM network
  # vmbr2199 - External/provider network
  ```

### 2. Storage Configuration

Check available storage:
```bash
pvesm status
```

You need ~1TB free space in a storage pool (default: `local` or `local-lvm`)

### 3. Network Requirements

- Gateway at `10.1.199.254` must be reachable
- IP range `10.1.199.140-150` available
- DNS resolution or `/etc/hosts` entries

### 4. SSH Key Preparation

Create or add your SSH public keys:
```bash
cat ~/.ssh/id_rsa.pub > pub_keys
# Or add multiple keys:
cat ~/.ssh/id_ed25519.pub >> pub_keys
```

⚠️ **Important**: The `pub_keys` file must contain at least one valid SSH public key!

---

## Configuration

Edit `rook_ceph.conf` to match your environment:

```bash
vim rook_ceph.conf
```

### Key Settings to Review:

```bash
# Network - adjust to your Proxmox network
GATEWAY="10.1.199.254"
BASE_IP="10.1.199"
START_IP_SUFFIX=140        # os0 will be .140

# VM Resources
TEMPLATE_ID=4444           # Must be unused VM ID
OS0_ID=4140                # Jump host VM ID
NODE_COUNT=6               # Total worker nodes (os1-os6)

# OpenStack nodes (which VMs get extra RAM)
OPENSTACK_NODE_INDEXES=(5 6)  # os5 and os6
OPENSTACK_MEMORY_MB=32768      # 32GB for OpenStack

# OpenStack node list - add/remove as needed
OPENSTACK_NODE_LIST=(
  "os5:10.1.199.145"
  "os6:10.1.199.146"
)
```

---

## Phase 1: Deploy Kubernetes + Rook-Ceph

### Step 1: Create Cloud-Init Template

First time only:
```bash
./cloud-init-template.sh
```

This downloads Ubuntu 24.04 cloud image and creates VM template (ID 4444 by default).

### Step 2: Deploy Rook-Ceph Stack

Run the main deployment script:
```bash
./deploy_rook_ceph.sh
```

**Or use the legacy script** (functionally similar):
```bash
./1-rook-ceph.sh
```

### What This Does:

1. ✅ Creates 7 VMs (os0-os6) from the template
2. ✅ Configures networking and SSH keys
3. ✅ Connects to os0 (jump host)
4. ✅ Installs kubectl, k9s, Ansible, Kubespray
5. ✅ Deploys Kubernetes cluster (os1-os4)
6. ✅ Installs Rook-Ceph operator and cluster
7. ✅ Deploys Ceph toolbox and dashboard

### Expected Duration: 30-45 minutes

### Monitoring Progress:

The script runs commands on os0. To monitor manually:

```bash
# SSH to jump host
ssh ubuntu@10.1.199.140

# Watch Kubernetes deployment
cd kubespray
source .venv/bin/activate
ansible-playbook -i inventory/rook-ceph-k8s/hosts.yaml cluster.yml

# After K8s is up, watch Rook-Ceph pods
kubectl get pods -n rook-ceph -w
```

### Verification:

```bash
# SSH to os0
ssh ubuntu@10.1.199.140

# Check cluster
kubectl get nodes
kubectl get pods -n rook-ceph

# Check Ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

Expected output:
```
  cluster:
    id:     <cluster-id>
    health: HEALTH_OK

  services:
    mon: 3 daemons
    mgr: 1 daemon
    osd: 8 osds: 8 up, 8 in
```

---

## Phase 2: Deploy OpenStack

### Prerequisites Check:

Before deploying OpenStack:
1. ✅ Kubernetes cluster is healthy
2. ✅ All Rook-Ceph pods are Running
3. ✅ Ceph cluster status is HEALTH_OK
4. ✅ os5 and os6 VMs are booted and accessible

### Step 1: Deploy OpenStack

```bash
./deploy_openstack.sh
```

**Or use the legacy script**:
```bash
./2-os.sh
```

### What This Does:

1. ✅ Connects to os0 (jump host)
2. ✅ Installs Kolla-Ansible
3. ✅ Generates multinode inventory for os5, os6
4. ✅ Creates Ceph pools (volumes, images, backups, vms)
5. ✅ Extracts Ceph credentials from Rook
6. ✅ Configures Kolla with Ceph backend
7. ✅ Runs Kolla-Ansible bootstrap
8. ✅ Deploys OpenStack services in containers
9. ✅ Runs post-deployment configuration

### Expected Duration: 45-60 minutes

### Monitoring Progress:

```bash
# SSH to os0
ssh ubuntu@10.1.199.140

# Watch Kolla-Ansible deployment
cd kolla
source .venv/bin/activate
tail -f /var/log/kolla/deploy.log  # (if logging enabled)

# Check Docker containers on OpenStack nodes
ssh ubuntu@10.1.199.145
docker ps | grep kolla
```

### Verification:

```bash
# On os0 jump host
ssh ubuntu@10.1.199.140

# Source OpenStack credentials
source /etc/kolla/admin-openrc.sh

# Check services
pip install python-openstackclient  # (if not already installed)
openstack service list
openstack compute service list
openstack network agent list
openstack volume service list

# Access Horizon dashboard
# URL: http://10.1.199.150 (or your VIP)
# User: admin
# Password: (from /etc/kolla/passwords.yml)
grep keystone_admin_password /etc/kolla/passwords.yml
```

---

## Phase 3: Post-Deployment Configuration

### 1. Initialize OpenStack Resources

```bash
# On os0
cd ~/kolla
source .venv/bin/activate

# Edit init-runonce script for your network
vim init-runonce

# Look for these lines and adjust network ranges:
# EXT_NET_CIDR='10.2.199.0/24'
# EXT_NET_RANGE='start=10.2.199.100,end=10.2.199.200'
# EXT_NET_GATEWAY='10.2.199.254'

# Run initialization
./init-runonce
```

This creates:
- Default flavors (m1.tiny, m1.small, etc.)
- Default network and subnet
- Cirros test image
- Security group rules

### 2. Upload Additional Images (Optional)

```bash
# Download Ubuntu cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Upload to Glance
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --public \
  --property os_type=linux \
  --file noble-server-cloudimg-amd64.img \
  Ubuntu-24.04
```

### 3. Create Test Instance

```bash
# Create keypair
ssh-keygen -t rsa -b 2048 -f ~/.ssh/test_key -N ""
openstack keypair create --public-key ~/.ssh/test_key.pub test_key

# Launch instance
openstack server create \
  --flavor m1.small \
  --image cirros \
  --network demo-net \
  --key-name test_key \
  test-vm

# Assign floating IP
FLOATING_IP=$(openstack floating ip create public1 -f value -c floating_ip_address)
openstack server add floating ip test-vm $FLOATING_IP

# Access via console or SSH
openstack console url show test-vm
ssh cirros@$FLOATING_IP  # Password: gocubsgo
```

---

## Troubleshooting

### Issue: VMs not getting IP addresses

```bash
# Check cloud-init on a VM
ssh ubuntu@10.1.199.141
sudo cloud-init status
sudo cat /var/log/cloud-init.log
```

### Issue: Kubernetes nodes not joining

```bash
# On os0
cd kubespray
source .venv/bin/activate

# Check Ansible logs
tail -f /tmp/ansible.log  # (if logging enabled)

# Manually check node
ssh ubuntu@10.1.199.141
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
```

### Issue: Ceph cluster unhealthy

```bash
# On os0
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash

# Inside toolbox
ceph status
ceph osd tree
ceph health detail
```

### Issue: OpenStack services not starting

```bash
# On OpenStack node
ssh ubuntu@10.1.199.145
docker ps -a | grep -v Up  # Show stopped containers
docker logs <container_id>

# Check Kolla logs
ls -la /var/log/kolla/
```

### Issue: Can't access Horizon dashboard

```bash
# Verify VIP is active
ssh ubuntu@10.1.199.145
ip addr show | grep 10.1.199.150

# Check HAProxy
docker logs haproxy

# Test from os0
curl -k http://10.1.199.150
```

---

## Cleanup / Teardown

**Warning**: This will destroy all VMs and data!

```bash
# On Proxmox host
# List VMs created
qm list | grep -E "4140|414[1-6]"

# Stop all VMs
for i in {4140..4146}; do qm stop $i; done

# Delete all VMs
for i in {4140..4146}; do qm destroy $i; done

# Optional: Remove template
qm destroy 4444
```

---

## Next Steps

After successful deployment:

1. **Explore Kubernetes**:
   - Deploy sample applications
   - Test persistent volumes with Rook-Ceph
   - Access Ceph dashboard (via port-forward or ingress)

2. **Explore OpenStack**:
   - Create networks, subnets, routers
   - Launch instances with volumes
   - Test Cinder backups to Ceph
   - Explore Masakari HA features

3. **Integration Testing**:
   - Test Ceph storage performance
   - Validate OpenStack-Ceph integration
   - Test disaster recovery scenarios

4. **Learn & Experiment**:
   - This is a safe sandbox environment
   - Try breaking things and fixing them
   - Document your findings for future reference
