
# Openstack and Rook/Ceph Cluster

This repository contains scripts to automate the creation of a 4-node Kubernetes cluster with Rook/Ceph storage and OpenStack deployment. It supports **multiple hypervisors** through an abstraction layer:

- **Proxmox VE** - Traditional datacenter hypervisor with web management
- **Cloud Hypervisor** - Lightweight, modern VMM for cloud-native deployments
- **Hybrid Mode** - Cloud Hypervisor VMs on Proxmox infrastructure (best of both worlds)

---

## 🧩 Features

- **Multi-Hypervisor Support**: Deploy on Proxmox VE or Cloud Hypervisor (bare metal Linux)
- **Automated VM creation** with hypervisor abstraction layer
- **7-VM cluster**: 1 jump host + 4 Kubernetes nodes + 2 OpenStack nodes
- **Kubespray-based** Kubernetes installation
- **Rook-Ceph** storage cluster deployment
- **Kolla-Ansible** OpenStack deployment with Ceph integration
- **Multi-network interfaces** (internal management + external provider)
- **Cloud-init** automated configuration
- **VM template** creation from Ubuntu 24.04 Cloud image

---

## 📦 Requirements

### For Proxmox VE

- A working [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) hypervisor (7.x or later)
- Proxmox CLI access (run as `root`)
- Network bridges: `vmbr1199` (internal) and `vmbr2199` (external)

### For Cloud Hypervisor

- Bare metal Linux server (Ubuntu 24.04 LTS recommended)
- CPU with virtualization support (Intel VT-x or AMD-V)
- Minimum 64GB RAM, 500GB disk
- KVM kernel modules loaded
- Root/sudo access for network bridge configuration

### Common Requirements

- Internet access to download images and packages
- SSH public key in `pub_keys` file

---

## 🚀 Quick Start

### Option 1: Proxmox VE (Traditional)

```bash
# Clone repository
git clone https://github.com/senolcolak/openstack-ceph-virtualized.git
cd openstack-ceph-virtualized

# Create cloud-init VM template (one-time setup)
./cloud-init-template.sh

# Add your SSH public key
cat ~/.ssh/id_rsa.pub > pub_keys

# Deploy full stack (7 VMs + Kubernetes + Rook-Ceph)
./deploy_rook_ceph.sh

# Deploy OpenStack (after Rook-Ceph is ready)
./deploy_openstack.sh
```

### Option 2: Cloud Hypervisor (Bare Metal)

```bash
# Clone repository
git clone https://github.com/senolcolak/openstack-ceph-virtualized.git
cd openstack-ceph-virtualized

# Setup Cloud Hypervisor host (installs CH, creates bridges, downloads template)
sudo ./setup-cloud-hypervisor.sh

# Add your SSH public key
cat ~/.ssh/id_rsa.pub > pub_keys

# Set hypervisor to Cloud Hypervisor (or let auto-detect)
export HYPERVISOR=cloudhypervisor

# Deploy full stack
./deploy_rook_ceph.sh

# Deploy OpenStack
./deploy_openstack.sh
```

### Option 3: Hybrid Mode (Cloud Hypervisor on Proxmox)

```bash
# Clone repository
git clone https://github.com/senolcolak/openstack-ceph-virtualized.git
cd openstack-ceph-virtualized

# Setup hybrid mode (installs CH on Proxmox, verifies bridges)
sudo ./setup-hybrid-mode.sh

# Add your SSH public key
cat ~/.ssh/id_rsa.pub > pub_keys

# Deploy with hybrid mode (Cloud Hypervisor VMs using Proxmox bridges)
HYPERVISOR=proxmox-cloudhypervisor ./deploy_rook_ceph.sh

# Deploy OpenStack
./deploy_openstack.sh
```

---

## 📖 Hypervisor Selection

The system automatically detects your hypervisor, but you can force a specific one:

```bash
# Auto-detect (default)
./deploy_rook_ceph.sh

# Force Proxmox
HYPERVISOR=proxmox ./deploy_rook_ceph.sh

# Force Cloud Hypervisor
HYPERVISOR=cloudhypervisor ./deploy_rook_ceph.sh

# Force Hybrid Mode (Cloud Hypervisor on Proxmox)
HYPERVISOR=proxmox-cloudhypervisor ./deploy_rook_ceph.sh
```

Or set in `rook_ceph.conf`:

```bash
HYPERVISOR="auto"  # auto, proxmox, cloudhypervisor, proxmox-cloudhypervisor
```

---

## 🔄 Hypervisor Comparison

| Feature | Proxmox VE | Cloud Hypervisor | Hybrid Mode |
|---------|-----------|------------------|-------------|
| **Installation** | Full OS | Single binary | Proxmox + CH binary |
| **Management** | Web GUI + CLI | CLI only | Web GUI for Proxmox VMs, CLI for CH VMs |
| **Setup Time** | Hours | Minutes | Minutes (on existing Proxmox) |
| **Resource Usage** | ~500MB per VM | ~100MB per VM | ~100MB per CH VM |
| **Boot Time** | ~30 seconds | ~20 seconds | ~20 seconds (CH VMs) |
| **Best For** | Datacenter, production | Bare metal, dev/test | Mixed workloads, testing |
| **Network** | Own bridges | Own bridges | Reuses Proxmox bridges |

**Choose Proxmox** if you:
- Want a web UI for management
- Need live migration and HA
- Have an existing Proxmox infrastructure

**Choose Cloud Hypervisor** if you:
- Want minimal overhead
- Are deploying on bare metal Linux
- Prefer CLI-driven workflows
- Need fast iteration for development

**Choose Hybrid Mode** if you:
- Already have Proxmox installed
- Want to test Cloud Hypervisor without dedicating hardware
- Need lightweight VMs alongside Proxmox VMs
- Want to leverage existing Proxmox network configuration

---

## 📚 Documentation

- **[Cloud Hypervisor Guide](docs/CLOUD_HYPERVISOR.md)** - Complete guide for Cloud Hypervisor deployment
- **[Hybrid Mode Guide](docs/HYBRID_MODE.md)** - Run Cloud Hypervisor on Proxmox infrastructure
- **[Hypervisor Abstraction](docs/HYPERVISOR_ABSTRACTION.md)** - Developer guide for multi-hypervisor architecture
- **[Project Architecture](docs/ARCHITECTURE.md)** - System design and component overview

---

## 📄 License

MIT License

---

## 👤 Author

Created by [Şenol Çolak](https://github.com/senolcolak) – [Kubedo](https://kubedo.io)

---

## 📬 Contributions

Pull requests and suggestions are welcome! Feel free to fork and enhance for your custom use cases.
