# Project Overview

## Purpose

This project automates the creation of a **fully virtualized cloud infrastructure** using Proxmox VE as the hypervisor. It deploys:

1. **Kubernetes cluster** (4 nodes) with **Rook-Ceph** distributed storage
2. **OpenStack cloud platform** (2+ nodes) using **Kolla-Ansible**
3. **Ceph storage integration** between Kubernetes and OpenStack

The goal is to simulate a production-grade cloud environment in a virtual lab for testing, development, or training purposes.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Proxmox VE Host                        │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Kubernetes Cluster (4 VMs)              │  │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐            │  │
│  │  │ os1  │  │ os2  │  │ os3  │  │ os4  │            │  │
│  │  │k8s-cp│  │k8s-wk│  │k8s-wk│  │k8s-wk│            │  │
│  │  └──────┘  └──────┘  └──────┘  └──────┘            │  │
│  │           Rook-Ceph Storage Layer                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                           ↕                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          OpenStack Cloud (2+ VMs)                    │  │
│  │  ┌──────┐  ┌──────┐                                 │  │
│  │  │ os5  │  │ os6  │  (Controller + Compute nodes)   │  │
│  │  │32GB  │  │32GB  │                                 │  │
│  │  └──────┘  └──────┘                                 │  │
│  │  Kolla-Ansible deployed OpenStack services          │  │
│  │  (Nova, Neutron, Cinder, Glance, Horizon, etc.)     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ os0 - Jump Host (140) - 8GB RAM                      │  │
│  │ • Ansible/Kubespray deployment controller            │  │
│  │ • kubectl access to K8s cluster                      │  │
│  │ • Kolla-Ansible deployment controller                │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Network Layout

- **Primary Network**: `vmbr1199` → VM interface `eth0`
  - IP Range: `10.1.199.0/24`
  - Gateway: `10.1.199.254`
  - Jump host (os0): `10.1.199.140`
  - K8s nodes (os1-os4): `10.1.199.141-144`
  - OpenStack nodes (os5-os6): `10.1.199.145-146`
  - OpenStack VIP: `10.1.199.150`

- **External Network**: `vmbr2199` → VM interface `ens19`
  - Used for OpenStack external/provider networks
  - Neutron external interface for floating IPs

---

## Components

### 1. Kubernetes Cluster (Rook-Ceph)
- **Tool**: Kubespray (Ansible-based K8s installer)
- **CNI**: Calico
- **Storage**: Rook-Ceph (provides block, file, object storage)
- **Nodes**: 4 VMs (os1-os4)
  - os1: Control plane + Worker + etcd
  - os2-os4: Worker nodes
- **Resources per node**: 4 vCPU, 8GB RAM, 3 disks (25GB system + 2x100GB for Ceph OSDs)

### 2. OpenStack Cloud (Kolla-Ansible)
- **Tool**: Kolla-Ansible (containerized OpenStack deployment)
- **Nodes**: 2+ VMs (os5-os6, configurable)
- **Services enabled**:
  - Core: Keystone, Glance, Nova, Neutron, Cinder, Horizon
  - Advanced: Masakari (HA/auto-recovery), Neutron VPNaaS, DVR
- **Storage backend**: External Ceph (from Rook cluster)
- **Resources per node**: 4 vCPU, 32GB RAM (higher for OpenStack workloads)

### 3. Storage Integration
- Rook-Ceph cluster provides storage pools for OpenStack:
  - `images`: Glance image storage
  - `volumes`: Cinder block volumes
  - `backups`: Cinder volume backups
  - `vms`: Nova ephemeral storage
- Ceph credentials (keyrings) are generated and injected into Kolla configuration

---

## Workflow Overview

### Phase 1: Rook-Ceph Deployment (`1-rook-ceph.sh` / `deploy_rook_ceph.sh`)
1. Create cloud-init VM template (Ubuntu 24.04)
2. Clone template to create 7 VMs (os0-os6)
3. Configure networking, SSH keys, storage disks
4. On os0 (jump host):
   - Install kubectl, k9s, Ansible
   - Clone Kubespray
   - Generate Kubernetes inventory from configuration
   - Deploy K8s cluster using Kubespray
   - Deploy Rook-Ceph operator and cluster
   - Expose Ceph dashboard via hostNetwork

### Phase 2: OpenStack Deployment (`2-os.sh` / `deploy_openstack.sh`)
1. On os0 (jump host):
   - Install Kolla-Ansible in virtualenv
   - Generate multinode inventory for OpenStack nodes
   - Create Ceph pools (volumes, images, backups, vms)
   - Extract Ceph configuration and keyrings from Rook
   - Generate `globals.yml` with Ceph backend configuration
   - Run Kolla-Ansible bootstrap, deploy, post-deploy
   - Activate external network interfaces on compute nodes

---

## Key Scripts

| Script | Purpose | Runs On |
|--------|---------|---------|
| `1-rook-ceph.sh` | Orchestrates full Rook-Ceph deployment | Proxmox host |
| `deploy_rook_ceph.sh` | New refactored version of above | Proxmox host |
| `2-os.sh` | Orchestrates OpenStack deployment | Proxmox host |
| `deploy_openstack.sh` | New refactored version of above | Proxmox host |
| `create-k8s.sh` | Legacy K8s-only deployment script | Proxmox host |
| `create-vm.sh` | Helper to clone and configure a single VM | Proxmox host |
| `cloud-init-template.sh` | Creates Ubuntu cloud-init template | Proxmox host |
| `rook_ceph.conf` | **Central configuration file** (all variables) | Proxmox host |
| `pub_keys` | SSH public keys for VM access | Proxmox host |

---

## Configuration Management

All configuration is centralized in `rook_ceph.conf`:
- Network settings (IPs, gateway, bridges)
- VM IDs, memory, node count
- Kubespray and Kolla-Ansible settings
- Ceph pool names
- OpenStack service configuration

**This is the single source of truth** - modify this file to customize your deployment.

---

## Current State Assessment

### ✅ What Works Well
1. **Modular design**: Separate scripts for K8s and OpenStack phases
2. **Unified configuration**: `rook_ceph.conf` centralizes all settings
3. **Automation**: End-to-end deployment with minimal manual intervention
4. **Storage integration**: Clean Ceph integration between K8s and OpenStack
5. **Production-like**: Uses industry-standard tools (Kubespray, Kolla-Ansible, Rook)

### ⚠️ Areas for Improvement
1. **Error handling**: Scripts use `set -e` but lack retry logic for transient failures
2. **Idempotency**: Re-running scripts may fail if VMs already exist
3. **Validation**: No pre-flight checks for Proxmox prerequisites (storage, network bridges)
4. **Documentation**: README is outdated (references old script names)
5. **Hardcoded values**: Some scripts have hardcoded IPs instead of using config
6. **SSH key management**: `pub_keys` file is empty in repo
7. **Testing**: No automated tests or validation steps
8. **Cleanup**: No teardown/cleanup script provided

### 🐛 Known Issues
1. `1-rook-ceph.sh` line 115: Uses `dpkg -i $(wget -qO-)` which downloads to stdout (should save to file first)
2. `create-k8s.sh` vs `1-rook-ceph.sh`: Duplicate functionality, unclear which is current
3. `2-os.sh`: Hardcoded IP addresses (`OS0=10.1.199.140`) instead of using config
4. Array syntax inconsistency in bash scripts (some use proper bash arrays, others parse strings)
5. Missing validation that Rook-Ceph cluster is healthy before OpenStack deployment

---

## Requirements

### Proxmox Host
- Proxmox VE 7.x or newer
- At least 64GB RAM (recommended: 128GB)
- Network bridges configured:
  - `vmbr1199` - Internal network
  - `vmbr2199` - External network
- Storage pool with sufficient space (~1TB recommended)
- Root/sudo access

### Network Prerequisites
- Routable subnet for VMs (default: `10.1.199.0/24`)
- Gateway accessible at `10.1.199.254`
- DNS resolution (or local `/etc/hosts` entries)

### Time Requirements
- Phase 1 (Rook-Ceph): ~30-45 minutes
- Phase 2 (OpenStack): ~45-60 minutes
- Total: ~1.5-2 hours for full deployment

---

## Use Cases

1. **Development/Testing**: Test OpenStack features without bare-metal infrastructure
2. **Training**: Learn Kubernetes, Ceph, and OpenStack administration
3. **CI/CD**: Automated testing of cloud-native applications
4. **POC/Demos**: Demonstrate cloud capabilities to stakeholders
5. **Disaster Recovery**: Test backup/restore procedures in isolated environment

---

## Security Considerations

⚠️ **This is NOT production-ready**:
- SSH host key checking disabled (`StrictHostKeyChecking=no`)
- Passwords auto-generated but stored in plaintext
- No TLS/SSL for most services
- Default Ceph authentication
- No network segmentation/firewalls
- Cloud-init user has passwordless sudo

**Use only in isolated lab environments.**
