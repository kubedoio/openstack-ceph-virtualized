# Documentation Index

Welcome to the OpenStack-Ceph Virtualized Infrastructure documentation.

---

## Quick Links

- **[Project Overview](PROJECT_OVERVIEW.md)** - Understanding the project's purpose and architecture
- **[Installation Guide](INSTALLATION_GUIDE.md)** - Step-by-step deployment instructions
- **[Architecture Documentation](ARCHITECTURE.md)** - Detailed technical architecture
- **[Configuration Reference](CONFIGURATION.md)** - All configuration options explained
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions

---

## Document Summaries

### [Project Overview](PROJECT_OVERVIEW.md)
**What you'll learn:**
- The project's purpose and use cases
- High-level architecture diagram
- Components breakdown (Kubernetes, Rook-Ceph, OpenStack)
- Workflow overview (Phase 1: K8s, Phase 2: OpenStack)
- Network layout and IP addressing
- Current state assessment (what works, what needs improvement)
- Security considerations
- Requirements and prerequisites

**Best for:** First-time users, project stakeholders, high-level understanding

---

### [Installation Guide](INSTALLATION_GUIDE.md)
**What you'll learn:**
- Prerequisites checklist (Proxmox, network, storage, SSH keys)
- Configuration steps for `rook_ceph.conf`
- Phase 1: Deploy Kubernetes + Rook-Ceph (detailed steps)
- Phase 2: Deploy OpenStack (detailed steps)
- Phase 3: Post-deployment configuration
- Verification commands
- Cleanup/teardown procedures

**Best for:** Users deploying the system for the first time, DevOps engineers

---

### [Architecture Documentation](ARCHITECTURE.md)
**What you'll learn:**
- System architecture (nested virtualization layers)
- Network topology and interface mapping
- Kubernetes cluster design (control plane, workers, CNI)
- Rook-Ceph storage architecture (MONs, MGRs, OSDs, pools)
- OpenStack service deployment model (all services explained)
- Data flow diagrams (VM launch, volume creation, image upload)
- Component communication matrix (ports, protocols)
- Storage disk layout and capacity planning
- Scalability considerations
- Security architecture and recommendations
- Monitoring and observability
- Backup and disaster recovery strategies
- Performance bottlenecks and optimization tips

**Best for:** System architects, advanced users, understanding internals

---

### [Configuration Reference](CONFIGURATION.md)
**What you'll learn:**
- Detailed explanation of every parameter in `rook_ceph.conf`
- SSH key configuration (`pub_keys` file)
- Kubespray inventory structure
- Kolla-Ansible `globals.yml` tunables
- Kolla `passwords.yml` management
- Rook-Ceph cluster.yaml customization
- Ceph configuration and keyrings
- Cloud-init configuration
- Environment variables
- Configuration validation techniques
- Troubleshooting configuration issues
- Configuration best practices
- Configuration templates for different scenarios

**Best for:** Users customizing the deployment, troubleshooting config issues

---

### [Troubleshooting Guide](TROUBLESHOOTING.md)
**What you'll learn:**
- General troubleshooting methodology
- Deployment phase issues (template creation, VM creation, SSH)
- Kubernetes deployment issues (Kubespray failures, node join issues)
- Rook-Ceph issues (operator not starting, OSDs not starting, health warnings)
- OpenStack deployment issues (Kolla bootstrap, service startup, Horizon access)
- Networking issues (internet access, inter-node communication)
- Storage/Ceph issues (volume creation, image upload)
- Performance issues and tuning
- Cleanup and recovery procedures
- Log locations for all components
- Useful diagnostic commands
- Community resources

**Best for:** Diagnosing failures, fixing broken deployments, understanding errors

---

## Getting Started Workflow

1. **Start here:** [Project Overview](PROJECT_OVERVIEW.md)
   - Understand what you're building
   - Check if your environment meets requirements

2. **Configure:** [Configuration Reference](CONFIGURATION.md)
   - Edit `rook_ceph.conf` for your environment
   - Prepare SSH keys

3. **Deploy:** [Installation Guide](INSTALLATION_GUIDE.md)
   - Follow phase-by-phase deployment steps
   - Verify each phase before proceeding

4. **Troubleshoot:** [Troubleshooting Guide](TROUBLESHOOTING.md)
   - Refer to this if you encounter issues
   - Check common error patterns

5. **Deep Dive:** [Architecture Documentation](ARCHITECTURE.md)
   - Understand how components interact
   - Plan customizations or enhancements

---

## Quick Reference Tables

### Network Addressing
| VM | Hostname | IP | Role | RAM |
|----|----------|-----|------|-----|
| os0 | os0.cluster.local | 10.1.199.140 | Jump host | 8GB |
| os1 | os1.cluster.local | 10.1.199.141 | K8s control+worker | 8GB |
| os2 | os2.cluster.local | 10.1.199.142 | K8s worker | 8GB |
| os3 | os3.cluster.local | 10.1.199.143 | K8s worker | 8GB |
| os4 | os4.cluster.local | 10.1.199.144 | K8s worker | 8GB |
| os5 | os5 | 10.1.199.145 | OpenStack all-in-one | 32GB |
| os6 | os6 | 10.1.199.146 | OpenStack all-in-one | 32GB |
| VIP | - | 10.1.199.150 | OpenStack HA VIP | - |

### Script Reference
| Script | Purpose | Phase |
|--------|---------|-------|
| `cloud-init-template.sh` | Create Ubuntu cloud-init template | Setup |
| `create-vm.sh` | Helper to create single VM | Setup |
| `deploy_rook_ceph.sh` | Deploy K8s + Rook-Ceph | Phase 1 |
| `1-rook-ceph.sh` | Legacy version of above | Phase 1 |
| `deploy_openstack.sh` | Deploy OpenStack + Ceph integration | Phase 2 |
| `2-os.sh` | Legacy version of above | Phase 2 |
| `create-k8s.sh` | Standalone K8s deployment (no Rook) | Alternative |

### Port Reference
| Service | Port | Protocol | Access From |
|---------|------|----------|-------------|
| SSH | 22 | TCP | Proxmox host, os0 |
| K8s API | 6443 | HTTPS | os0 |
| Ceph MON | 6789 | TCP | K8s nodes, OpenStack |
| Ceph MGR | 8443 | HTTPS | Browser (dashboard) |
| Horizon | 80 | HTTP | Browser |
| Keystone API | 5000 | HTTP | CLI clients |
| Nova API | 8774 | HTTP | CLI clients |
| Neutron API | 9696 | HTTP | CLI clients |
| Cinder API | 8776 | HTTP | CLI clients |

### Common Commands

**Check overall status:**
```bash
# Proxmox VMs
qm list | grep 414

# Kubernetes cluster
kubectl get nodes
kubectl get pods --all-namespaces

# Ceph cluster
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# OpenStack services
source /etc/kolla/admin-openrc.sh
openstack service list
openstack compute service list
```

**Access dashboards:**
```bash
# Ceph dashboard (port-forward from os0)
kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard 8443:8443
# Access: https://localhost:8443

# Get Ceph dashboard password
kubectl -n rook-ceph get secret rook-ceph-dashboard-password \
  -o jsonpath="{['data']['password']}" | base64 --decode

# Horizon dashboard
# Access: http://10.1.199.150
# Username: admin
# Password: grep keystone_admin_password /etc/kolla/passwords.yml
```

**SSH to VMs:**
```bash
# Jump host
ssh ubuntu@10.1.199.140

# Kubernetes nodes
ssh ubuntu@10.1.199.141  # os1 (control-plane)
ssh ubuntu@10.1.199.142  # os2 (worker)

# OpenStack nodes
ssh ubuntu@10.1.199.145  # os5
ssh ubuntu@10.1.199.146  # os6
```

---

## Document Maintenance

### Version History
- **v1.0** (2026-03-04): Initial comprehensive documentation
  - Project Overview
  - Installation Guide
  - Architecture Documentation
  - Configuration Reference
  - Troubleshooting Guide

### Contributing
Improvements to this documentation are welcome! When updating:

1. Keep language clear and concise
2. Use code blocks for commands
3. Include expected output where helpful
4. Add warnings (⚠️) for destructive operations
5. Cross-reference related sections
6. Update this index when adding new documents

### Feedback
If you find errors, unclear sections, or missing information:
- Open an issue: https://github.com/senolcolak/proxmox-k8s4rook/issues
- Or contribute a fix via pull request

---

## Additional Resources

### Official Documentation
- **Proxmox VE**: https://pve.proxmox.com/pve-docs/
- **Kubernetes**: https://kubernetes.io/docs/
- **Kubespray**: https://kubespray.io/
- **Rook**: https://rook.io/docs/rook/latest/
- **Ceph**: https://docs.ceph.com/
- **OpenStack**: https://docs.openstack.org/
- **Kolla-Ansible**: https://docs.openstack.org/kolla-ansible/latest/

### Community
- **Kubespray GitHub**: https://github.com/kubernetes-sigs/kubespray
- **Rook Slack**: https://rook.io/slack
- **OpenStack IRC**: #openstack on OFTC
- **Proxmox Forum**: https://forum.proxmox.com/

### Related Projects
- **OpenStack-Helm**: Kubernetes-native OpenStack deployment
- **Charmed OpenStack**: Juju-based OpenStack deployment
- **DevStack**: Developer-focused OpenStack all-in-one
- **MicroStack**: Snap-based OpenStack deployment

---

## License & Attribution

This project and documentation created by **Şenol Çolak** ([Kubedo](https://kubedo.io)).

**License**: MIT License (see [LICENSE](../LICENSE) file)

**Contributing**: Pull requests welcome!

**Support**: For commercial support or consulting, visit [kubedo.io](https://kubedo.io)

---

## Glossary

**Ceph**: Distributed storage system providing block, object, and file storage
**Cephx**: Ceph authentication protocol using shared secret keys
**DVR**: Distributed Virtual Router (Neutron feature for distributed L3 routing)
**etcd**: Distributed key-value store used by Kubernetes
**Glance**: OpenStack image service
**HAProxy**: High availability load balancer
**Horizon**: OpenStack web dashboard
**Keystone**: OpenStack identity service
**Kolla-Ansible**: Ansible-based tool for deploying OpenStack in containers
**Kubespray**: Ansible-based tool for deploying Kubernetes
**Masakari**: OpenStack high availability service for auto-recovery
**MON**: Ceph monitor daemon
**MGR**: Ceph manager daemon
**Neutron**: OpenStack networking service
**Nova**: OpenStack compute service
**OSD**: Ceph object storage daemon
**PG**: Placement group (Ceph data distribution unit)
**RBD**: RADOS Block Device (Ceph block storage)
**Rook**: Kubernetes operator for running Ceph
**VIP**: Virtual IP (floating IP for HA services)
**VMBR**: Virtual bridge in Proxmox

---

*Last updated: 2026-03-04*
