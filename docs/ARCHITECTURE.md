# Architecture Documentation

## System Architecture

### High-Level Design

This project implements a **nested virtualization architecture** where:
- **Layer 1**: Proxmox VE (bare metal hypervisor)
- **Layer 2**: Virtual machines running Kubernetes and OpenStack
- **Layer 3**: OpenStack can spawn additional VMs inside the cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                    Physical Server (Proxmox VE)                 │
│                                                                 │
│  ┌─────────────────────────────────┐  ┌────────────────────┐  │
│  │  Kubernetes Cluster (Layer 2)   │  │ OpenStack (Layer 2)│  │
│  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐   │  │  ┌────┐  ┌────┐   │  │
│  │  │os1 │ │os2 │ │os3 │ │os4 │   │  │  │os5 │  │os6 │   │  │
│  │  └────┘ └────┘ └────┘ └────┘   │  │  └────┘  └────┘   │  │
│  │                                 │  │                    │  │
│  │  ┌──────────────────────────┐  │  │  ┌──────────────┐ │  │
│  │  │     Rook-Ceph Cluster    │  │  │  │ Guest VMs    │ │  │
│  │  │  (Distributed Storage)   │◄─┼──┼──┤  (Layer 3)   │ │  │
│  │  └──────────────────────────┘  │  │  └──────────────┘ │  │
│  └─────────────────────────────────┘  └────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              os0 - Jump/Deployment Host                  │  │
│  │  • Kubespray • Kolla-Ansible • kubectl • openstack-cli  │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Network Architecture

### Network Topology

```
                    ┌─────────────────┐
                    │  Gateway/Router │
                    │  10.1.199.254   │
                    └────────┬────────┘
                             │
        ┌────────────────────┴──────────────────────┐
        │                                           │
   ┌────▼──────┐                             ┌─────▼─────┐
   │  vmbr1199 │                             │ vmbr2199  │
   │ (Internal)│                             │(External) │
   └────┬──────┘                             └─────┬─────┘
        │                                          │
        │ eth0                                     │ ens19
   ┌────┴─────────────────────────────────────────┴────┐
   │                                                    │
   │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
   │  │ os0  │  │ os1  │  │ os2  │  │ os3  │  ...    │
   │  │.140  │  │.141  │  │.142  │  │.143  │         │
   │  └──────┘  └──────┘  └──────┘  └──────┘         │
   │                                                    │
   │  OpenStack VIP: 10.1.199.150                      │
   │                                                    │
   └────────────────────────────────────────────────────┘
```

### Network Interfaces

| Interface | Bridge | Purpose | Connected VMs |
|-----------|--------|---------|---------------|
| eth0 | vmbr1199 | Internal management | All VMs (os0-os6) |
| ens19 | vmbr2199 | External/Provider network | OpenStack nodes (os5-os6) |

### IP Address Allocation

| VM | Hostname | IP Address | Role |
|-----|----------|------------|------|
| os0 | os0.cluster.local | 10.1.199.140 | Jump host / Deployment controller |
| os1 | os1.cluster.local | 10.1.199.141 | K8s control-plane + worker + etcd |
| os2 | os2.cluster.local | 10.1.199.142 | K8s worker |
| os3 | os3.cluster.local | 10.1.199.143 | K8s worker |
| os4 | os4.cluster.local | 10.1.199.144 | K8s worker |
| os5 | os5 | 10.1.199.145 | OpenStack controller+compute |
| os6 | os6 | 10.1.199.146 | OpenStack controller+compute |
| VIP | - | 10.1.199.150 | OpenStack HA virtual IP |

**Configurable**: All IPs are derived from `rook_ceph.conf`:
```bash
BASE_IP="10.1.199"
START_IP_SUFFIX=140  # os0 starts here
```

---

## Kubernetes Architecture

### Cluster Design

```
┌────────────────────────────────────────────────────┐
│           Kubernetes Cluster (v1.29+)              │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │              Control Plane (os1)             │ │
│  │  • kube-apiserver                            │ │
│  │  • kube-controller-manager                   │ │
│  │  • kube-scheduler                            │ │
│  │  • etcd (single node)                        │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │          Worker Nodes (os1-os4)              │ │
│  │  • kubelet                                   │ │
│  │  • kube-proxy                                │ │
│  │  • Container runtime (containerd)            │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │          CNI: Calico                         │ │
│  │  • Pod network: 10.233.0.0/16 (default)     │ │
│  │  • Service network: 10.233.64.0/18          │ │
│  └──────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────┘
```

### Kubernetes Components

- **Deployment Tool**: Kubespray (Ansible-based)
- **Container Runtime**: containerd
- **CNI Plugin**: Calico
- **DNS**: CoreDNS
- **Ingress**: Not deployed (can be added)
- **Load Balancer**: Not deployed (can add MetalLB)

### Key Configuration

- **Control plane**: Single node (os1) - not HA
- **etcd**: Single node (os1) - not HA
- **Worker nodes**: 4 nodes (os1-os4) - all nodes run workloads
- **kubeconfig**: Generated on os1, copied to os0 for kubectl access

**Production Note**: This is a single control-plane setup. For HA, configure 3 control-plane nodes in Kubespray inventory.

---

## Rook-Ceph Architecture

### Storage Cluster Design

```
┌──────────────────────────────────────────────────────────┐
│              Rook-Ceph Cluster (rook-ceph ns)            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Rook Operator (os1)                      │ │
│  │  • Orchestrates Ceph daemons                       │ │
│  │  • Manages CRDs (CephCluster, CephBlockPool, etc.) │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Ceph Monitors (MONs) x3                  │ │
│  │  • Cluster membership and state                    │ │
│  │  • Running on os1, os2, os3                        │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Ceph Managers (MGRs) x2                  │ │
│  │  • Dashboard, metrics, orchestration               │ │
│  │  • Active/standby HA                               │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Ceph OSDs (Object Storage Daemons)       │ │
│  │  • 8 OSDs total (2 per node)                       │ │
│  │  • scsi1: 100GB, scsi2: 100GB per VM              │ │
│  │  • Replication factor: 3 (default)                 │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Ceph Metadata Servers (MDS) - Optional   │ │
│  │  • CephFS filesystem support                       │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Tools & Services                         │ │
│  │  • rook-ceph-tools (debug pod)                     │ │
│  │  • Ceph Dashboard (HTTP on hostNetwork)            │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Storage Pools

Created automatically for OpenStack:

| Pool Name | Purpose | OpenStack Service | Default Size |
|-----------|---------|-------------------|--------------|
| `volumes` | Block storage volumes | Cinder | Varies |
| `images` | VM images | Glance | Varies |
| `backups` | Volume backups | Cinder Backup | Varies |
| `vms` | Ephemeral VM disks | Nova | Varies |

### Ceph Configuration

- **Replication**: 3 replicas (default Ceph behavior)
- **Min replicas**: 2 (for write operations)
- **PG autoscaling**: Enabled
- **hostNetwork**: `true` (exposes Ceph dashboard outside K8s)

### Authentication

Ceph uses **cephx** authentication:
- Cluster-to-cluster auth required
- Client auth required
- Keyrings generated for each OpenStack service:
  - `client.glance`
  - `client.cinder`
  - `client.cinder-backup`
  - `client.nova` (inherits from cinder)

---

## OpenStack Architecture

### Service Deployment

```
┌────────────────────────────────────────────────────────┐
│         OpenStack Cloud (Kolla-Ansible deployed)       │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Identity (Keystone)                 │ │
│  │  • Authentication and authorization              │ │
│  │  • Service catalog                               │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Image (Glance)                      │ │
│  │  • VM image storage (Ceph RBD backend)           │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Compute (Nova)                      │ │
│  │  • nova-api, nova-conductor, nova-scheduler      │ │
│  │  • nova-compute (libvirt/KVM)                    │ │
│  │  • Ephemeral storage on Ceph                     │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Network (Neutron)                   │ │
│  │  • neutron-server, neutron-dhcp-agent            │ │
│  │  • neutron-l3-agent, neutron-metadata-agent      │ │
│  │  • neutron-openvswitch-agent                     │ │
│  │  • DVR (Distributed Virtual Router) enabled      │ │
│  │  • VPNaaS enabled                                │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Block Storage (Cinder)              │ │
│  │  • cinder-api, cinder-scheduler                  │ │
│  │  • cinder-volume (Ceph RBD backend)              │ │
│  │  • cinder-backup (Ceph RBD backend)              │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Dashboard (Horizon)                 │ │
│  │  • Web UI for cloud management                   │ │
│  │  • VIP: http://10.1.199.150                      │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              HA/Recovery (Masakari)              │ │
│  │  • Auto-recovery for failed hosts/instances      │ │
│  │  • masakari-api, masakari-engine                 │ │
│  │  • masakari-instancemonitor                      │ │
│  │  • masakari-hostmonitor                          │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              Load Balancer (HAProxy)             │ │
│  │  • VIP management (keepalived)                   │ │
│  │  • API endpoint load balancing                   │ │
│  └──────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

### Deployment Model

- **Containerized**: All services run in Docker containers
- **Orchestration**: Kolla-Ansible (Docker Compose under the hood)
- **Distribution**: Ubuntu base images
- **Configuration management**: Jinja2 templates + Ansible
- **Multi-node**: os5 and os6 both run controller + compute roles

### High Availability

Limited HA in this setup:
- **HAProxy + Keepalived**: Provides VIP failover for API endpoints
- **Masakari**: Auto-recovery for instance/host failures
- **No** multi-region or multi-AZ setup
- **No** redundant control plane (requires 3+ nodes)

**Production Note**: For true HA, deploy dedicated controller nodes (3+) separate from compute nodes.

---

## Data Flow Diagrams

### VM Launch Flow (OpenStack)

```
User → Horizon/CLI
         ↓
    Keystone (auth)
         ↓
    Nova API
         ↓
    Nova Scheduler (select compute host)
         ↓
    Nova Compute (os5 or os6)
         ↓
    Libvirt (create VM)
         ↓
    Neutron (attach network)
         ↓
    Cinder (attach volume - optional)
         ↓
    ┌────────────────┐
    │ Ceph Cluster   │ ← Volume data stored here
    │ (Rook-managed) │
    └────────────────┘
```

### Volume Creation Flow (Cinder → Ceph)

```
openstack volume create
         ↓
    Cinder API
         ↓
    Cinder Scheduler
         ↓
    Cinder Volume (os5/os6)
         ↓
    Ceph RBD driver
         ↓
    Ceph client.cinder keyring
         ↓
    ┌────────────────────────────┐
    │  Kubernetes os1-os4        │
    │    ┌───────────────┐       │
    │    │ Rook Operator │       │
    │    └───────┬───────┘       │
    │            ↓               │
    │    ┌──────────────┐        │
    │    │  Ceph OSDs   │        │
    │    │  (volumes    │        │
    │    │   pool)      │        │
    │    └──────────────┘        │
    └────────────────────────────┘
```

### Image Upload Flow (Glance → Ceph)

```
openstack image create --file image.qcow2
         ↓
    Glance API
         ↓
    Glance Registry
         ↓
    Ceph RBD driver (glance backend)
         ↓
    Ceph client.glance keyring
         ↓
    ┌────────────────┐
    │ Ceph Cluster   │
    │ (images pool)  │
    └────────────────┘
```

---

## Component Communication Matrix

| Source | Target | Protocol | Port | Purpose |
|--------|--------|----------|------|---------|
| os0 | os1-os6 | SSH | 22 | Ansible deployment |
| os0 | os1 | HTTPS | 6443 | kubectl → K8s API |
| K8s nodes | Ceph OSDs | TCP | 6789, 3300 | Ceph MON/MGR communication |
| OpenStack | K8s Ceph | TCP | 6789, 3300, 6800-7300 | Ceph client → cluster |
| os5/os6 | os5/os6 VIP | HTTP/HTTPS | 80, 443 | API endpoint access |
| User | OpenStack VIP | HTTP | 80 | Horizon dashboard |
| User | OpenStack VIP | HTTPS | 5000 | Keystone API |
| User | OpenStack VIP | TCP | 8774 | Nova API |
| User | OpenStack VIP | TCP | 9696 | Neutron API |
| User | OpenStack VIP | TCP | 8776 | Cinder API |
| Nova compute | Neutron L3/DHCP | Various | Various | VM networking |

---

## Storage Architecture

### Disk Layout per VM

**Kubernetes nodes (os1-os4)**:
```
┌────────────┐  ┌────────────┐  ┌────────────┐
│   scsi0    │  │   scsi1    │  │   scsi2    │
│  (system)  │  │ (Ceph OSD) │  │ (Ceph OSD) │
│   50GB     │  │   100GB    │  │   100GB    │
└────────────┘  └────────────┘  └────────────┘
```

**OpenStack nodes (os5-os6)**:
```
┌────────────┐  ┌────────────┐  ┌────────────┐
│   scsi0    │  │   scsi1    │  │   scsi2    │
│  (system)  │  │  (unused)  │  │  (unused)  │
│   50GB     │  │   100GB    │  │   100GB    │
└────────────┘  └────────────┘  └────────────┘
```

**Jump host (os0)**:
```
┌────────────┐
│   scsi0    │
│  (system)  │
│   50GB     │
└────────────┘
```

### Ceph Storage Capacity

With 8 OSDs @ 100GB each:
- **Raw capacity**: 800GB
- **Usable capacity** (3x replication): ~267GB
- **Recommended max usage**: 80% → ~213GB available

---

## Scalability Considerations

### Scaling Kubernetes Cluster
- Add more VMs to `create-vm.sh` loop
- Update Kubespray inventory (`hosts.yaml`)
- Re-run Kubespray playbook with `scale.yml`

### Scaling OpenStack Cluster
- Add VM entries to `OPENSTACK_NODE_LIST` in `rook_ceph.conf`
- Update Kolla multinode inventory
- Run `kolla-ansible deploy` to add nodes

### Scaling Ceph Storage
- Add more OSDs per VM (scsi3, scsi4, etc.)
- Add more K8s nodes with OSDs
- Rook will auto-detect and add new OSDs

**Limits**:
- Proxmox host resources (RAM, CPU, storage)
- Single control-plane becomes bottleneck
- Network bandwidth on single bridge

---

## Security Architecture

### Current Security Posture

⚠️ **Warning**: This is NOT production-ready!

**Authentication**:
- ✅ SSH key-based auth (but keys in plaintext `pub_keys`)
- ✅ Ceph cephx authentication
- ✅ OpenStack Keystone auth
- ❌ No TLS/SSL on most endpoints
- ❌ SSH host key checking disabled
- ❌ Passwords stored in plaintext (`/etc/kolla/passwords.yml`)

**Network Security**:
- ❌ No firewall rules between VMs
- ❌ No network segmentation (all VMs on same subnet)
- ❌ No encryption for Ceph client-cluster communication
- ❌ Services exposed on hostNetwork without restrictions

**Access Control**:
- ✅ Ubuntu user has sudo (required for deployment)
- ❌ No RBAC policies defined for Kubernetes
- ❌ Default OpenStack admin credentials

**Recommendations for Production**:
1. Enable TLS for all API endpoints (Kolla supports this)
2. Use Ansible Vault for secrets
3. Implement network policies in Kubernetes
4. Configure Ceph encryption at rest
5. Use separate management network
6. Enable audit logging
7. Implement proper RBAC in K8s and OpenStack
8. Use certificate management (Let's Encrypt, internal CA)

---

## Monitoring & Observability

### Built-in Dashboards

**Ceph Dashboard**:
```bash
# Find dashboard pod
kubectl -n rook-ceph get svc | grep dashboard

# Port-forward to access
kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard 8443:8443

# Get admin password
kubectl -n rook-ceph get secret rook-ceph-dashboard-password \
  -o jsonpath="{['data']['password']}" | base64 --decode
```

**OpenStack Horizon**:
- URL: `http://10.1.199.150`
- Username: `admin`
- Password: `grep keystone_admin_password /etc/kolla/passwords.yml`

### Recommended Additions

For better observability:
- **Prometheus + Grafana**: Monitor K8s and Ceph metrics
- **ELK/EFK Stack**: Centralized logging
- **Ceph Prometheus exporter**: Detailed storage metrics
- **OpenStack Telemetry** (Ceilometer): Usage metrics

---

## Backup & Disaster Recovery

### Current State
- ❌ No automated backups configured
- ✅ Ceph replication (3x) provides data redundancy
- ✅ Cinder backup service available (backs up to Ceph)

### Manual Backup Procedures

**Kubernetes config**:
```bash
# Backup etcd
kubectl -n kube-system get pod -l component=etcd
# (Use Kubespray backup playbooks)
```

**Ceph data**:
```bash
# Snapshot RBD image
rbd snap create volumes/volume-xyz@snapshot1
rbd snap protect volumes/volume-xyz@snapshot1
```

**OpenStack config**:
```bash
# Backup Kolla configs
tar -czf kolla-backup.tar.gz /etc/kolla/
```

### Recovery Procedures
- Restore etcd from backup
- Re-deploy K8s using Kubespray
- Re-deploy OpenStack using Kolla-Ansible
- Ceph data persists on OSDs (survives container restarts)

---

## Performance Considerations

### Bottlenecks

1. **Network**: Single bridge shared by all VMs
   - Solution: Use multiple bridges, SR-IOV, or bonding

2. **Storage**: Nested virtualization overhead
   - Ceph OSDs running in VMs on virtual disks
   - Solution: Use physical disks with PCI passthrough

3. **CPU**: Overcommitment if host resources limited
   - 7 VMs × 4 vCPU = 28 vCPUs needed
   - Solution: Reduce VM count or vCPU allocation

4. **Memory**: 168GB RAM needed (os0:8GB + os1-os4:32GB + os5-os6:64GB)
   - Solution: Reduce OpenStack node RAM if testing only

### Optimization Tips

- Use `local-lvm` storage pool (faster than directory-based)
- Enable CPU host passthrough for better performance
- Disable unnecessary OpenStack services in `globals.yml`
- Use Ceph cache tiers (if adding SSDs)
- Tune Ceph PG counts for workload

---

## Future Architecture Enhancements

### Short-term
- [ ] Add ingress controller (NGINX/Traefik) for K8s
- [ ] Deploy Prometheus/Grafana monitoring
- [ ] Enable TLS for OpenStack APIs
- [ ] Add MetalLB for K8s LoadBalancer services
- [ ] Implement proper RBAC policies

### Medium-term
- [ ] Multi-control-plane K8s (HA)
- [ ] Dedicated OpenStack controller nodes
- [ ] Separate storage network
- [ ] CephFS deployment for shared filesystems
- [ ] Object storage (RGW) for S3-compatible storage

### Long-term
- [ ] Multi-region OpenStack deployment
- [ ] Federation with external K8s clusters
- [ ] Automated DR and backup solutions
- [ ] Performance profiling and optimization
- [ ] CI/CD integration for automated testing
