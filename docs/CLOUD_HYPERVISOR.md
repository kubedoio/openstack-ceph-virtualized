# Cloud Hypervisor Support

This document provides a complete guide for deploying the OpenStack-Ceph infrastructure using **Cloud Hypervisor** on bare metal Linux servers.

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Networking](#networking)
- [Storage](#storage)
- [Troubleshooting](#troubleshooting)
- [Comparison with Proxmox](#comparison-with-proxmox)

## Overview

Cloud Hypervisor is a modern, lightweight Virtual Machine Monitor (VMM) focused on running cloud workloads. This project now supports both Proxmox VE and Cloud Hypervisor through a unified abstraction layer.

### Why Cloud Hypervisor?

- **Lightweight**: Minimal resource overhead (~100MB per VM vs ~500MB on Proxmox)
- **Fast**: Quick boot times (~20 seconds)
- **Cloud-native**: Designed for cloud workloads
- **Simple**: No complex management UI, straightforward CLI
- **Bare metal**: Runs directly on Linux without requiring full hypervisor infrastructure

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Deployment Scripts (deploy_rook_ceph.sh, create-vm.sh)    │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │  Hypervisor Abstraction  │ (lib/hypervisor.sh)
        └────────┬─────────┬───────┘
                 │         │
    ┌────────────┴──┐   ┌──┴─────────────┐
    │  Proxmox VE   │   │ Cloud Hypervisor│
    │  (qm)         │   │  (ch-remote)    │
    └───────────────┘   └─────────────────┘
```

## Requirements

### Hardware

- **CPU**: x86_64 with virtualization support (Intel VT-x or AMD-V)
- **RAM**: Minimum 64GB (for 7 VMs: 1x 8GB + 4x 8GB + 2x 32GB)
- **Disk**: 500GB+ (for VM images and Ceph storage)
- **Network**: 2 NICs recommended (internal + external)

### Software

- **Operating System**: Ubuntu 24.04 LTS or similar (bare metal)
- **Kernel**: 5.15+ with KVM support
- **Packages**: qemu-utils, genisoimage, bridge-utils, iproute2, iptables

### Verification

Check virtualization support:
```bash
# Check CPU virtualization
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should be > 0

# Check KVM modules
lsmod | grep kvm  # Should show kvm_intel or kvm_amd

# Load KVM modules if needed
sudo modprobe kvm kvm_intel  # or kvm_amd for AMD
```

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/openstack-ceph-virtualized.git
cd openstack-ceph-virtualized
```

### Step 2: Run the Setup Script

The setup script automates Cloud Hypervisor installation and configuration:

```bash
sudo ./setup-cloud-hypervisor.sh
```

This script will:
1. Install required packages (qemu-utils, genisoimage, etc.)
2. Download and install Cloud Hypervisor binaries
3. Create network bridges (chbr1199, chbr2199)
4. Configure IP forwarding and NAT
5. Download Ubuntu 24.04 cloud image template
6. Create systemd service for persistent bridge configuration

### Step 3: Verify Installation

After setup completes, verify the installation:

```bash
# Check Cloud Hypervisor
cloud-hypervisor --version
ch-remote --version

# Check network bridges
ip link show chbr1199
ip link show chbr2199

# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1
```

## Configuration

### Basic Configuration

Edit `rook_ceph.conf` to configure your deployment. The hypervisor is auto-detected, but you can force it:

```bash
# Hypervisor selection
HYPERVISOR="auto"              # auto, proxmox, cloudhypervisor

# Cloud Hypervisor specific
CH_VM_DIR="/var/lib/cloud-hypervisor/vms"
CH_IMAGE_DIR="/var/lib/cloud-hypervisor/images"
CH_API_SOCKET="/run/cloud-hypervisor"
CH_USE_API="yes"

# Network configuration (unchanged)
GATEWAY="10.1.199.254"
BASE_IP="10.1.199"
START_IP_SUFFIX=140

# VM configuration
TEMPLATE_ID=4444
OS0_ID=4140
NODE_COUNT=6
```

### Network Configuration

Cloud Hypervisor uses Linux bridges instead of Proxmox's vmbr:

- **chbr1199** - Internal management network (10.1.199.0/24) → VM's eth0
- **chbr2199** - External provider network (10.2.199.0/24) → VM's ens19

These are automatically created by `setup-cloud-hypervisor.sh`.

### Storage Configuration

VM disks are stored as raw sparse files:

```bash
# VM directory structure
/var/lib/cloud-hypervisor/
├── vms/
│   ├── vm-4140/              # Jump host (os0)
│   │   ├── system.raw        # System disk (50GB)
│   │   ├── disk-1.raw        # OSD disk 1 (100GB)
│   │   ├── disk-2.raw        # OSD disk 2 (100GB)
│   │   ├── cloudinit.iso     # Cloud-init configuration
│   │   └── config.json       # VM configuration
│   ├── vm-4141/              # Worker node (os1)
│   └── ...
└── images/
    └── template-4444.raw     # Ubuntu 24.04 template
```

## Deployment

### Full Deployment

Deploy the entire stack (7 VMs + Kubernetes + Rook-Ceph):

```bash
# Ensure you have SSH keys
cat ~/.ssh/id_rsa.pub > pub_keys

# Run deployment
./deploy_rook_ceph.sh
```

The script will:
1. Create 7 VMs (1 jump host + 6 worker nodes)
2. Install Kubernetes with Kubespray on 4 nodes (os1-os4)
3. Deploy Rook-Ceph storage cluster
4. Configure OpenStack nodes (os5-os6) with extra RAM

### Manual VM Creation

Create individual VMs for testing:

```bash
# Create a single VM
./create-vm.sh 4444 4141 os1.cluster.local 10.1.199.141/24 10.1.199.254

# Start the VM
source lib/hypervisor.sh
hv_init
hv_start_vm 4141

# Check status
hv_vm_status 4141

# SSH into the VM (wait ~30 seconds for cloud-init)
ssh ubuntu@10.1.199.141
```

### Step-by-Step Deployment

For more control, deploy in phases:

```bash
# Phase 1: Create VMs only
./create-vm.sh 4444 4140 os0.cluster.local 10.1.199.140/24 10.1.199.254
./create-vm.sh 4444 4141 os1.cluster.local 10.1.199.141/24 10.1.199.254
# ... repeat for os2-os6

# Phase 2: Start VMs
source lib/hypervisor.sh
hv_init
for vm_id in 4140 4141 4142 4143 4144 4145 4146; do
  hv_start_vm $vm_id
done

# Phase 3: Wait for cloud-init
sleep 30

# Phase 4: Continue with Kubespray deployment
# (follow remaining steps in deploy_rook_ceph.sh)
```

## Networking

### Bridge Architecture

```
┌────────────────────────────────────────────────────────┐
│  Host (Bare Metal Linux Server)                       │
│                                                         │
│  ┌──────────────┐              ┌──────────────┐      │
│  │  chbr1199     │              │  chbr2199     │      │
│  │  10.1.199.254 │              │  10.2.199.254 │      │
│  └──────┬────────┘              └──────┬────────┘      │
│         │                              │                │
│    ┌────┴─────┬────────┬───────┐ ┌────┴─────┬────┐  │
│    │          │        │       │ │          │    │  │
│  tap-0-0  tap-1-0  tap-2-0  ... tap-0-1  tap-1-1 ... │
│    │          │        │           │          │        │
└────┼──────────┼────────┼───────────┼──────────┼────────┘
     │          │        │           │          │
   ┌─┴──┐    ┌─┴──┐  ┌─┴──┐      ┌─┴──┐    ┌─┴──┐
   │VM 0│    │VM 1│  │VM 2│      │VM 0│    │VM 1│
   │eth0│    │eth0│  │eth0│      │ens19│   │ens19│
   └────┘    └────┘  └────┘      └────┘    └────┘
```

### TAP Device Naming

TAP devices follow this pattern: `tap-<vm_id>-<interface_index>`

Example for VM 4141:
- `tap-4141-0` → chbr1199 (internal, eth0 in VM)
- `tap-4141-1` → chbr2199 (external, ens19 in VM)

### Network Troubleshooting

```bash
# List all bridges
ip link show type bridge

# List all TAP devices
ip tuntap list mode tap

# Check bridge members
bridge link show

# Test connectivity from host
ping 10.1.199.141

# Check NAT rules
iptables -t nat -L -n -v
```

## Storage

### Disk Layout

Each VM has 3 disks:
1. **system.raw** - OS disk (50GB, expanded from template)
2. **disk-1.raw** - Ceph OSD disk 1 (100GB sparse)
3. **disk-2.raw** - Ceph OSD disk 2 (100GB sparse)

### Disk Format

All disks use **raw** format for Cloud Hypervisor:

```bash
# Check disk info
qemu-img info /var/lib/cloud-hypervisor/vms/vm-4141/system.raw

# Resize disk
qemu-img resize /var/lib/cloud-hypervisor/vms/vm-4141/system.raw +10G

# Convert qcow2 to raw (if needed)
qemu-img convert -f qcow2 -O raw source.qcow2 dest.raw
```

### Storage Management

```bash
# Check disk usage
du -sh /var/lib/cloud-hypervisor/vms/vm-*

# List all VM disks
find /var/lib/cloud-hypervisor/vms -name "*.raw" -exec ls -lh {} \;

# Clean up stopped VM
source lib/hypervisor.sh
hv_init
hv_destroy_vm 4141  # Removes VM and all disks
```

## Troubleshooting

### VM Won't Start

**Check VM configuration:**
```bash
cat /var/lib/cloud-hypervisor/vms/vm-4141/config.json | jq
```

**Check cloud-hypervisor logs:**
```bash
tail -f /var/lib/cloud-hypervisor/vms/vm-4141/console.log
```

**Check if process is running:**
```bash
ps aux | grep cloud-hypervisor
cat /var/lib/cloud-hypervisor/vms/vm-4141/vm.pid
```

**Manually start VM for debugging:**
```bash
cloud-hypervisor \
  --api-socket /run/cloud-hypervisor/vm-4141.sock \
  --cpus boot=4 \
  --memory size=8192M \
  --disk path=/var/lib/cloud-hypervisor/vms/vm-4141/system.raw \
  --net tap=tap-4141-0 \
  --serial tty \
  --console off
```

### Network Issues

**Check bridges:**
```bash
ip link show chbr1199
ip link show chbr2199
```

**Recreate bridges:**
```bash
source lib/common/network.sh
setup_cloudhypervisor_network
```

**Check TAP devices:**
```bash
ip tuntap list | grep tap-4141
```

**Recreate TAP device:**
```bash
source lib/common/network.sh
delete_tap_device tap-4141-0
create_tap_device tap-4141-0 chbr1199
```

**Check IP forwarding:**
```bash
cat /proc/sys/net/ipv4/ip_forward  # Should be 1
sudo sysctl -w net.ipv4.ip_forward=1
```

### Cloud-Init Issues

**Check cloud-init ISO:**
```bash
isoinfo -f -i /var/lib/cloud-hypervisor/vms/vm-4141/cloudinit.iso
```

**Extract and inspect:**
```bash
mkdir /tmp/cloudinit
sudo mount -o loop /var/lib/cloud-hypervisor/vms/vm-4141/cloudinit.iso /tmp/cloudinit
cat /tmp/cloudinit/user-data
cat /tmp/cloudinit/meta-data
sudo umount /tmp/cloudinit
```

**Regenerate cloud-init ISO:**
```bash
source lib/common/cloudinit.sh
generate_cloudinit_iso \
  /tmp/test.iso \
  vm-4141 \
  os1 \
  os1.cluster.local \
  10.1.199.141/24 \
  10.1.199.254 \
  pub_keys
```

### SSH Connection Refused

**Wait for cloud-init to complete:**
```bash
# Cloud-init can take 30-60 seconds on first boot
sleep 60
ssh ubuntu@10.1.199.141
```

**Check VM is actually running:**
```bash
source lib/hypervisor.sh
hv_init
hv_vm_status 4141
```

**Check from host network:**
```bash
ping 10.1.199.141
```

**Check cloud-init status (from VM console):**
```bash
# If you have serial console access
cloud-init status --wait
```

## Comparison with Proxmox

| Feature | Proxmox VE | Cloud Hypervisor |
|---------|-----------|------------------|
| **Installation** | Full OS installation | Single binary |
| **Management** | Web GUI + CLI | CLI only |
| **Resource Usage** | ~500MB per VM | ~100MB per VM |
| **Boot Time** | ~30 seconds | ~20 seconds |
| **Live Migration** | Yes | Experimental |
| **Snapshots** | Yes (GUI) | Manual (qemu-img) |
| **HA** | Yes | No (external) |
| **Backup** | Integrated | Manual scripts |
| **Console Access** | VNC + Serial | Serial only |
| **Cloud-Init** | Built-in | NoCloud ISO |
| **Networking** | vmbr bridges | Linux bridges |
| **Storage** | Multiple backends | Local raw/qcow2 |
| **Learning Curve** | Medium | Low |
| **Maturity** | Production | Modern, stable |

### When to Use Cloud Hypervisor

✅ **Good for:**
- Bare metal servers without Proxmox
- Cloud-native deployments
- Minimal overhead requirements
- CLI-driven workflows
- Development/testing environments
- Kubernetes/OpenStack infrastructure

❌ **Not ideal for:**
- Teams requiring GUI management
- Production workloads needing HA
- Scenarios requiring live migration
- Complex networking requirements
- Integrated backup solutions

## Advanced Topics

### Custom Bridge Configuration

Edit bridge IPs in `rook_ceph.conf`:

```bash
INTERNAL_BRIDGE="chbr1199"
INTERNAL_IP="10.1.199.254/24"
EXTERNAL_BRIDGE="chbr2199"
EXTERNAL_IP="10.2.199.254/24"
```

Then recreate bridges:

```bash
sudo ./setup-cloud-hypervisor.sh
```

### API Socket Access

Cloud Hypervisor VMs expose REST API via Unix socket:

```bash
# List VMs via API
ch-remote --api-socket /run/cloud-hypervisor/vm-4141.sock info

# Shutdown via API
ch-remote --api-socket /run/cloud-hypervisor/vm-4141.sock shutdown

# Reboot via API
ch-remote --api-socket /run/cloud-hypervisor/vm-4141.sock reboot
```

### Template Customization

Create custom templates:

```bash
# Download alternative image
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img

# Convert to raw
qemu-img convert -f qcow2 -O raw ubuntu-24.04-minimal-cloudimg-amd64.img \
  /var/lib/cloud-hypervisor/images/template-5555.raw

# Use in create-vm.sh
./create-vm.sh 5555 4150 test.local 10.1.199.150/24 10.1.199.254
```

## Support

For issues and questions:
- GitHub Issues: https://github.com/yourusername/openstack-ceph-virtualized/issues
- Cloud Hypervisor Docs: https://github.com/cloud-hypervisor/cloud-hypervisor
- Upstream Bug Reports: https://github.com/cloud-hypervisor/cloud-hypervisor/issues

## Next Steps

After successful Cloud Hypervisor deployment:

1. **Deploy OpenStack**: Run `./deploy_openstack.sh` to install Kolla-Ansible
2. **Configure Ceph**: Access Rook-Ceph operator and verify cluster health
3. **Create Networks**: Setup Neutron provider networks
4. **Launch Instances**: Create OpenStack VMs using Ceph storage

See [README.md](../README.md) for complete workflow.
