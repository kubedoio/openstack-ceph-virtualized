# Configuration Guide

This directory contains the new modular configuration system for the OpenStack-Ceph virtualized infrastructure project.

## 📁 Directory Structure

```
config/
├── default.conf          # Common settings (loaded first)
├── proxmox.conf         # Your Proxmox settings (copy from examples/)
├── cloudhypervisor.conf # Your Cloud Hypervisor settings (copy from examples/)
├── hybrid.conf          # Your Hybrid mode settings (copy from examples/)
├── examples/            # Example configurations (templates)
│   ├── proxmox.conf
│   ├── cloudhypervisor.conf
│   └── hybrid.conf
└── README.md            # This file
```

## 🎯 Quick Start

### 1. Choose Your Hypervisor

Pick the configuration that matches your deployment:

- **Proxmox VE**: Traditional datacenter hypervisor with web UI
- **Cloud Hypervisor**: Lightweight VMM for bare metal Linux
- **Hybrid Mode**: Cloud Hypervisor VMs on Proxmox infrastructure

### 2. Copy Example Configuration

```bash
# For Proxmox VE
cp config/examples/proxmox.conf config/proxmox.conf

# For Cloud Hypervisor
cp config/examples/cloudhypervisor.conf config/cloudhypervisor.conf

# For Hybrid Mode
cp config/examples/hybrid.conf config/hybrid.conf
```

### 3. Edit Your Configuration

```bash
# Edit the hypervisor-specific config
vi config/proxmox.conf        # or cloudhypervisor.conf or hybrid.conf

# Optionally edit common settings
vi config/default.conf
```

### 4. Set Hypervisor Type

Either edit `config/default.conf`:
```bash
HYPERVISOR="proxmox"   # or cloudhypervisor or proxmox-cloudhypervisor
```

Or export environment variable:
```bash
export HYPERVISOR=proxmox
```

### 5. Run Setup

```bash
# For Proxmox
./cloud-init-template.sh

# For Cloud Hypervisor
sudo ./setup-cloud-hypervisor.sh

# For Hybrid Mode
sudo ./setup-hybrid-mode.sh
```

## 📖 Configuration Files Explained

### config/default.conf

**Purpose**: Contains settings common to ALL hypervisors

**Contains**:
- Network configuration (IP ranges, gateways)
- VM settings (naming, resource allocation)
- Kubernetes configuration
- Rook-Ceph configuration
- OpenStack configuration
- SSH key settings

**When to edit**: When you need to change cluster-wide settings like IP ranges, VM names, or resource allocation.

### config/examples/proxmox.conf

**Purpose**: Proxmox VE specific settings

**Contains**:
- Template VM ID
- Proxmox bridge names (vmbr1199, vmbr2199)
- Storage pool configuration
- CPU and BIOS settings

**When to use**: Deploying on Proxmox VE hypervisor

### config/examples/cloudhypervisor.conf

**Purpose**: Cloud Hypervisor specific settings

**Contains**:
- VM and image storage directories
- Bridge names (chbr1199, chbr2199)
- Template configuration
- Cloud Hypervisor specific features

**When to use**: Deploying on bare metal Linux with Cloud Hypervisor

### config/examples/hybrid.conf

**Purpose**: Hybrid mode specific settings

**Contains**:
- Proxmox bridge mapping
- VM ID allocation (to avoid conflicts)
- TAP device naming
- Coexistence settings

**When to use**: Running Cloud Hypervisor VMs on Proxmox infrastructure

## 🔄 How Configuration Loading Works

1. **config/default.conf** is loaded first (common settings)
2. Hypervisor-specific config is loaded based on `HYPERVISOR` variable:
   - `proxmox` → loads `config/proxmox.conf`
   - `cloudhypervisor` → loads `config/cloudhypervisor.conf`
   - `proxmox-cloudhypervisor` → loads `config/hybrid.conf`
3. Later values override earlier values (hypervisor-specific overrides defaults)

## 🔧 Common Customizations

### Change IP Range

Edit `config/default.conf`:
```bash
GATEWAY="10.1.199.254"
BASE_IP="10.1.199"
START_IP_SUFFIX=140
```

### Change VM Resources

Edit `config/default.conf`:
```bash
DEFAULT_CORES=4
DEFAULT_MEMORY_MB=8192
OPENSTACK_MEMORY_MB=32768
```

### Change Proxmox Bridges

Edit `config/proxmox.conf`:
```bash
BRIDGE_INTERNAL="vmbr1199"
BRIDGE_EXTERNAL="vmbr2199"
```

### Change Cloud Hypervisor Storage

Edit `config/cloudhypervisor.conf`:
```bash
CH_VM_DIR="/var/lib/cloud-hypervisor/vms"
CH_IMAGE_DIR="/var/lib/cloud-hypervisor/images"
```

### Change Hybrid Mode VM ID Start

Edit `config/hybrid.conf`:
```bash
HYBRID_VM_ID_START=5000
```

## 🔀 Migrating from Old Configuration

If you have an existing `rook_ceph.conf` file:

1. **Backup your old config**:
   ```bash
   cp rook_ceph.conf rook_ceph.conf.backup
   ```

2. **Copy common settings** to `config/default.conf`:
   - Network settings (GATEWAY, BASE_IP, etc.)
   - VM settings (NODE_COUNT, VM_PREFIX, etc.)
   - Kubernetes, OpenStack, Ceph settings

3. **Copy hypervisor-specific settings** to appropriate config:
   - Proxmox: TEMPLATE_ID, bridges → `config/proxmox.conf`
   - Cloud Hypervisor: CH_* variables → `config/cloudhypervisor.conf`
   - Hybrid: HYBRID_* variables → `config/hybrid.conf`

4. **Test the new configuration**:
   ```bash
   # Verify config loads correctly
   source config/default.conf
   source config/proxmox.conf  # or your hypervisor config

   # Check variables are set
   echo $HYPERVISOR
   echo $GATEWAY
   echo $TEMPLATE_ID
   ```

## 📋 Configuration Variables Reference

### Network Variables
- `GATEWAY`: Network gateway IP
- `BASE_IP`: First three octets of IP range
- `START_IP_SUFFIX`: Starting suffix for VM IPs
- `NETWORK_INTERFACE`: Internal management interface
- `EXTERNAL_INTERFACE`: External provider interface

### VM Variables
- `VM_PREFIX`: Prefix for VM names (default: "os")
- `NODE_COUNT`: Number of nodes to create
- `OS0_ID`: VM ID for jump host
- `DEFAULT_CORES`: CPU cores per VM
- `DEFAULT_MEMORY_MB`: RAM per VM
- `OPENSTACK_NODE_INDEXES`: Which nodes get extra RAM
- `OPENSTACK_MEMORY_MB`: RAM for OpenStack nodes

### Hypervisor Variables
- `HYPERVISOR`: Hypervisor type (proxmox, cloudhypervisor, proxmox-cloudhypervisor)
- `TEMPLATE_ID`: Proxmox template VM ID
- `CH_VM_DIR`: Cloud Hypervisor VM storage
- `CH_IMAGE_DIR`: Cloud Hypervisor image storage
- `HYBRID_BRIDGE_INTERNAL`: Hybrid mode internal bridge
- `HYBRID_BRIDGE_EXTERNAL`: Hybrid mode external bridge
- `HYBRID_VM_ID_START`: Starting VM ID for hybrid mode

### Kubernetes Variables
- `KUBESPRAY_DIR`: Kubespray directory
- `INVENTORY_NAME`: Ansible inventory name
- `KUBERNETES_VERSION`: Kubernetes version

### OpenStack Variables
- `KOLLA_DIR`: Kolla-Ansible directory
- `OPENSTACK_INVENTORY_FILE`: Inventory filename
- `OPENSTACK_RELEASE`: OpenStack release name
- `OPENSTACK_NODE_LIST`: Array of OpenStack nodes
- `KOLLA_INTERNAL_VIP_ADDRESS`: Internal VIP
- `NEUTRON_EXTERNAL_INTERFACE`: Neutron external interface

### Ceph Variables
- `ROOK_VERSION`: Rook operator version
- `CEPH_VERSION`: Ceph version
- `CEPH_POOLS`: Array of Ceph pool names

## 🆘 Troubleshooting

### Configuration not loading

**Problem**: Variables are empty or not set

**Solution**:
1. Check HYPERVISOR variable is set:
   ```bash
   echo $HYPERVISOR
   ```

2. Verify config file exists:
   ```bash
   ls -l config/default.conf
   ls -l config/proxmox.conf  # or your hypervisor config
   ```

3. Source configs manually to test:
   ```bash
   source config/default.conf
   source config/proxmox.conf
   ```

### Wrong hypervisor config loaded

**Problem**: Proxmox settings loaded when using Cloud Hypervisor

**Solution**:
1. Check HYPERVISOR variable:
   ```bash
   echo $HYPERVISOR
   ```

2. Set it explicitly:
   ```bash
   export HYPERVISOR=cloudhypervisor
   ```

3. Or edit `config/default.conf`:
   ```bash
   HYPERVISOR="cloudhypervisor"
   ```

### Old rook_ceph.conf still used

**Problem**: Scripts loading old config file

**Solution**:
- Old scripts will still use `rook_ceph.conf` until they're updated
- New scripts will use modular configs
- Both can coexist during transition

## 📚 Additional Resources

- **Main Documentation**: See `/docs/` directory
- **Hypervisor Guides**:
  - Proxmox: `docs/hypervisors/proxmox.md`
  - Cloud Hypervisor: `docs/hypervisors/cloudhypervisor.md`
  - Hybrid: `docs/hypervisors/hybrid-mode.md`
- **Troubleshooting**: `docs/troubleshooting.md`

## ✅ Validation

Before deploying, validate your configuration:

```bash
# Validate configuration (coming soon)
./scripts/utils/validate-config.sh

# Check prerequisites (coming soon)
./scripts/utils/check-prerequisites.sh
```

## 🔍 Examples

### Example 1: Proxmox Deployment

```bash
# Copy example config
cp config/examples/proxmox.conf config/proxmox.conf

# Edit template ID
vi config/proxmox.conf
# Set: TEMPLATE_ID=4444

# Edit network if needed
vi config/default.conf
# Set: GATEWAY="10.1.199.254"

# Deploy
export HYPERVISOR=proxmox
./cloud-init-template.sh
./deploy_rook_ceph.sh
```

### Example 2: Cloud Hypervisor Deployment

```bash
# Copy example config
cp config/examples/cloudhypervisor.conf config/cloudhypervisor.conf

# Edit storage paths if needed
vi config/cloudhypervisor.conf
# CH_VM_DIR="/var/lib/cloud-hypervisor/vms"

# Setup and deploy
export HYPERVISOR=cloudhypervisor
sudo ./setup-cloud-hypervisor.sh
./deploy_rook_ceph.sh
```

### Example 3: Hybrid Mode Deployment

```bash
# Copy example config
cp config/examples/hybrid.conf config/hybrid.conf

# Verify Proxmox bridges
vi config/hybrid.conf
# HYBRID_BRIDGE_INTERNAL="vmbr1199"
# HYBRID_BRIDGE_EXTERNAL="vmbr2199"

# Setup and deploy
export HYPERVISOR=proxmox-cloudhypervisor
sudo ./setup-hybrid-mode.sh
./deploy_rook_ceph.sh
```

---

**Need help?** Check the troubleshooting section above or refer to the main documentation in `/docs/`.
