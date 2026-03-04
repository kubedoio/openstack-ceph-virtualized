# Troubleshooting Guide

This guide covers common issues, error messages, and their solutions.

---

## General Troubleshooting Approach

1. **Identify the failure point**: Script output, Ansible logs, service logs
2. **Check dependencies**: Is the previous phase complete and healthy?
3. **Verify connectivity**: Can VMs reach each other and external networks?
4. **Review logs**: Most issues have clear error messages in logs
5. **Test manually**: SSH into VMs and run commands manually to isolate the issue

---

## Deployment Phase Issues

### Issue: Template Creation Fails

**Symptoms**:
```
ERROR: Failed to download cloud image
wget: unable to resolve host address
```

**Causes**:
- No internet access from Proxmox host
- DNS not configured

**Solutions**:
```bash
# Test DNS
ping google.com

# Fix DNS (if needed)
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Retry download manually
wget -N https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Verify image downloaded
ls -lh /root/noble-server-cloudimg-amd64.img
```

---

### Issue: VM Creation Fails

**Symptoms**:
```
Configuration file 'datacenter' does not exist
unable to create VM: unable to parse storage
```

**Causes**:
- Storage pool doesn't exist or is full
- Invalid storage name in script

**Solutions**:
```bash
# List available storage
pvesm status

# Check storage capacity
df -h /var/lib/vz

# If using local-lvm, ensure it exists
lvdisplay | grep local

# Edit create-vm.sh to use correct storage
vim create-vm.sh
# Change line: qm set $2 --scsi1 local:100
# To: qm set $2 --scsi1 <your-storage>:100
```

---

### Issue: Can't SSH to VMs

**Symptoms**:
```
ssh: connect to host 10.1.199.141 port 22: No route to host
Permission denied (publickey)
```

**Causes**:
- pub_keys file is empty or invalid
- Cloud-init hasn't finished
- Network misconfiguration
- SSH service not running

**Solutions**:
```bash
# Verify pub_keys file
cat pub_keys
# Should contain valid SSH public keys

# Wait for cloud-init (can take 2-3 minutes)
qm wait 4141

# Check VM console for errors
qm terminal 4141

# Verify network from Proxmox host
ping 10.1.199.141

# Check if SSH is listening
nc -zv 10.1.199.141 22

# Try with password (if configured)
ssh ubuntu@10.1.199.141
# Default cloud-init user: ubuntu (no password unless set)

# Regenerate SSH keys
rm pub_keys
cat ~/.ssh/id_rsa.pub > pub_keys

# Destroy and recreate VM
qm destroy 4141
./create-vm.sh 4444 4141 os1.cluster.local 10.1.199.141/24 10.1.199.254
qm start 4141
```

---

## Kubernetes Deployment Issues

### Issue: Kubespray Fails with Timeout

**Symptoms**:
```
TASK [kubernetes/preinstall : Install packages requirements] ***
fatal: [os1]: FAILED! => {"msg": "Failed to download metadata for repo 'appstream'"}
```

**Causes**:
- VMs can't reach internet (Ubuntu package repos)
- DNS not resolving

**Solutions**:
```bash
# SSH to problematic VM
ssh ubuntu@10.1.199.141

# Test internet connectivity
ping 8.8.8.8
ping archive.ubuntu.com

# Check DNS
cat /etc/resolv.conf
nslookup archive.ubuntu.com

# Fix DNS if needed
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# Test package installation
sudo apt update
sudo apt install -y curl

# Retry Kubespray from os0
cd kubespray
source .venv/bin/activate
ansible-playbook -i inventory/rook-ceph-k8s/hosts.yaml cluster.yml
```

---

### Issue: Nodes Not Joining Cluster

**Symptoms**:
```
kubectl get nodes
NAME   STATUS     ROLES           AGE   VERSION
os1    Ready      control-plane   10m   v1.29.0
os2    NotReady   <none>          5m    v1.29.0
```

**Causes**:
- Network plugin (Calico) not ready
- Node kubelet service failed
- Time synchronization issues

**Solutions**:
```bash
# Check kubelet status on NotReady node
ssh ubuntu@10.1.199.142
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50 --no-pager

# Check Calico pods
kubectl get pods -n kube-system | grep calico

# If Calico pods are stuck, check logs
kubectl logs -n kube-system <calico-pod-name>

# Restart kubelet
sudo systemctl restart kubelet

# Check time sync
timedatectl status
# If time is wrong:
sudo timedatectl set-ntp true
```

---

### Issue: kubectl Commands Fail

**Symptoms**:
```
The connection to the server 127.0.0.1:6443 was refused
Unable to connect to the server: dial tcp 10.1.199.141:6443: i/o timeout
```

**Causes**:
- kubeconfig not configured
- API server not running
- Firewall blocking port 6443

**Solutions**:
```bash
# Verify kubeconfig exists
ls -la ~/.kube/config

# Check API server from os1
ssh ubuntu@10.1.199.141
sudo systemctl status kube-apiserver
# Or (if using static pods):
sudo crictl ps | grep kube-apiserver

# Check API server logs
sudo journalctl -u kube-apiserver -n 50

# Test API server connectivity
curl -k https://10.1.199.141:6443/version

# Regenerate kubeconfig
ssh ubuntu@10.1.199.141 'sudo cat /etc/kubernetes/admin.conf' \
  | sed "s/127.0.0.1/10.1.199.141/g" > ~/.kube/config

# Verify
kubectl cluster-info
```

---

## Rook-Ceph Issues

### Issue: Rook Operator Not Starting

**Symptoms**:
```
kubectl get pods -n rook-ceph
NAME                                 READY   STATUS             RESTARTS
rook-ceph-operator-xxx               0/1     ImagePullBackOff
```

**Causes**:
- No internet access to pull container images
- Docker Hub rate limiting

**Solutions**:
```bash
# Check image pull status
kubectl describe pod -n rook-ceph rook-ceph-operator-xxx

# Test image pull manually from a node
ssh ubuntu@10.1.199.141
sudo crictl pull rook/ceph:latest

# If rate limited, wait or use a mirror
# Edit operator.yaml before applying:
vim ~/rook/deploy/examples/operator.yaml
# Change image: rook/ceph:latest
# To: image: quay.io/rook/ceph:latest

# Reapply
kubectl apply -f ~/rook/deploy/examples/operator.yaml
```

---

### Issue: Ceph OSDs Not Starting

**Symptoms**:
```
kubectl get pods -n rook-ceph
NAME                                     READY   STATUS
rook-ceph-osd-prepare-os1-xxx            0/1     Error
```

**Causes**:
- Disks not available or already in use
- Permissions issues

**Solutions**:
```bash
# Check OSD prepare logs
kubectl logs -n rook-ceph rook-ceph-osd-prepare-os1-xxx

# Common error: "disk already in use"
# SSH to node and check disks
ssh ubuntu@10.1.199.141
lsblk
sudo parted /dev/sdb print

# If disk has partitions or filesystem, wipe it
sudo wipefs -a /dev/sdb
sudo wipefs -a /dev/sdc

# Or use sgdisk (if GPT)
sudo sgdisk --zap-all /dev/sdb
sudo sgdisk --zap-all /dev/sdc

# Delete OSD prepare job and let it retry
kubectl delete job -n rook-ceph rook-ceph-osd-prepare-os1
```

---

### Issue: Ceph Cluster Not Healthy

**Symptoms**:
```
ceph status
  cluster:
    health: HEALTH_WARN
            too few PGs per OSD
            mon is allowing insecure global_id reclaim
```

**Causes**:
- Normal warnings for small clusters
- Not enough OSDs
- Time synchronization issues

**Solutions**:
```bash
# Access Ceph toolbox
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash

# Check detailed health
ceph health detail

# For "too few PGs" warning (safe to ignore in lab):
ceph config set global mon_max_pg_per_osd 500

# For "insecure global_id" warning:
ceph config set mon auth_allow_insecure_global_id_reclaim false

# Check OSD status
ceph osd tree
ceph osd stat

# Check time sync across nodes
for i in {141..144}; do
  echo "=== os at 10.1.199.$i ==="
  ssh ubuntu@10.1.199.$i 'date'
done
# If times differ by >30 seconds, fix NTP
```

---

### Issue: Can't Create Ceph Pools

**Symptoms**:
```
kubectl exec deploy/rook-ceph-tools -- ceph osd pool create volumes
Error ERANGE: too many PGs per OSD
```

**Causes**:
- Small cluster, too many pools requested
- PG autoscaling not active

**Solutions**:
```bash
# Create smaller pools
ceph osd pool create volumes 8
ceph osd pool create images 8
ceph osd pool create backups 8
ceph osd pool create vms 8

# Or enable autoscaling
ceph osd pool set volumes pg_autoscale_mode on

# Check PG distribution
ceph osd pool ls detail
```

---

## OpenStack Deployment Issues

### Issue: Kolla-Ansible Bootstrap Fails

**Symptoms**:
```
TASK [baremetal : Install docker apt package] ***
fatal: [os5]: FAILED! => {"changed": false, "msg": "Failed to install packages: docker-ce"}
```

**Causes**:
- Docker repo not configured
- Conflicting Docker versions

**Solutions**:
```bash
# SSH to failing node
ssh ubuntu@10.1.199.145

# Remove old Docker
sudo apt remove docker docker-engine docker.io containerd runc

# Install Docker manually
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu

# Test Docker
docker ps

# Retry bootstrap
cd ~/kolla
source .venv/bin/activate
kolla-ansible bootstrap-servers -i multinode
```

---

### Issue: Kolla Deploy Fails on Ceph Config

**Symptoms**:
```
TASK [cinder-volume : Copying ceph.conf] ***
fatal: [os5]: FAILED! => {"msg": "Could not find or access '/etc/kolla/config/cinder/ceph.conf'"}
```

**Causes**:
- Ceph config files not generated
- deploy_openstack.sh didn't complete

**Solutions**:
```bash
# Verify Ceph configs exist on os0
ssh ubuntu@10.1.199.140
ls -la /etc/kolla/config/cinder/
ls -la /etc/kolla/config/glance/

# If missing, regenerate manually:
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config generate-minimal-conf > /etc/ceph/ceph.conf

# Regenerate keyrings
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  ceph auth get-or-create client.cinder \
  mon 'profile rbd' \
  osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' \
  mgr 'profile rbd pool=volumes, profile rbd pool=vms' \
  > /etc/kolla/config/cinder/ceph.client.cinder.keyring

# Copy to other services
cp /etc/ceph/ceph.conf /etc/kolla/config/cinder/ceph.conf
cp /etc/ceph/ceph.conf /etc/kolla/config/glance/ceph.conf

# Retry deploy
cd ~/kolla
source .venv/bin/activate
kolla-ansible deploy -i multinode
```

---

### Issue: OpenStack Services Won't Start

**Symptoms**:
```
docker ps | grep keystone
# No output - container not running

docker ps -a | grep keystone
CONTAINER ID   IMAGE                          STATUS
xxx            kolla/ubuntu-keystone:latest   Exited (1)
```

**Causes**:
- Database connection failure
- Configuration errors
- Insufficient memory

**Solutions**:
```bash
# Check container logs
ssh ubuntu@10.1.199.145
docker logs <container-id>

# Common issue: Database not ready
docker ps | grep mariadb
# If MariaDB is down, restart it:
docker restart mariadb

# Check container resources
docker stats --no-stream

# If out of memory, increase VM RAM:
# On Proxmox host:
qm set 4145 --memory 65536  # 64GB

# Restart all Kolla containers
ssh ubuntu@10.1.199.145
cd /usr/local/share/kolla-ansible/ansible
docker-compose -f /etc/kolla/docker-compose.yml restart
```

---

### Issue: Can't Access Horizon Dashboard

**Symptoms**:
```
curl http://10.1.199.150
curl: (7) Failed to connect to 10.1.199.150 port 80: No route to host
```

**Causes**:
- VIP not active
- HAProxy not running
- Firewall blocking port 80

**Solutions**:
```bash
# Check VIP on OpenStack nodes
ssh ubuntu@10.1.199.145
ip addr show | grep 10.1.199.150
# Should show VIP on one of the nodes

# If VIP missing, check keepalived
docker logs keepalived

# Check HAProxy
docker ps | grep haproxy
docker logs haproxy

# Test from os0 (same network)
ssh ubuntu@10.1.199.140
curl -I http://10.1.199.150

# Restart HAProxy and keepalived
ssh ubuntu@10.1.199.145
docker restart haproxy keepalived
```

---

### Issue: OpenStack CLI Commands Fail

**Symptoms**:
```
openstack service list
Missing value auth-url required for auth plugin password
```

**Causes**:
- Environment variables not set
- admin-openrc.sh not sourced

**Solutions**:
```bash
# Source OpenStack credentials
source /etc/kolla/admin-openrc.sh

# Verify environment
env | grep OS_

# If file missing, regenerate:
cd ~/kolla
source .venv/bin/activate
kolla-ansible post-deploy -i multinode

# Test authentication
openstack token issue
```

---

## Networking Issues

### Issue: VMs Can't Reach Internet

**Symptoms**:
```
ssh ubuntu@10.1.199.141
ping 8.8.8.8
connect: Network is unreachable
```

**Causes**:
- Gateway not configured
- Proxmox bridge not routed
- Firewall blocking

**Solutions**:
```bash
# Check VM route table
ssh ubuntu@10.1.199.141
ip route show
# Should show: default via 10.1.199.254 dev eth0

# If missing, add manually:
sudo ip route add default via 10.1.199.254

# Make permanent (cloud-init override):
sudo vim /etc/netplan/50-cloud-init.yaml
# Add gateway4: 10.1.199.254 under eth0
sudo netplan apply

# On Proxmox host, verify bridge can reach gateway
ping 10.1.199.254
ip route show

# Enable IP forwarding on Proxmox (if needed)
sysctl net.ipv4.ip_forward
# If 0, enable:
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

---

### Issue: Nodes Can't Communicate

**Symptoms**:
```
ssh ubuntu@10.1.199.141
ping 10.1.199.142
# No response
```

**Causes**:
- Bridge firewall rules
- VM firewall (ufw)

**Solutions**:
```bash
# Check VM firewall
ssh ubuntu@10.1.199.141
sudo ufw status
# If active, disable (or allow specific ports):
sudo ufw disable

# On Proxmox host, check bridge firewall
pve-firewall status

# Disable Proxmox firewall temporarily
pve-firewall stop

# Or add rules:
vim /etc/pve/firewall/cluster.fw
# Add:
[RULES]
IN ACCEPT -i vmbr1199 -source 10.1.199.0/24 -dest 10.1.199.0/24
```

---

## Storage/Ceph Issues

### Issue: Cinder Volume Creation Fails

**Symptoms**:
```
openstack volume create --size 10 test-vol
ERROR: Build of volume xxx failed: Failed to create volume
```

**Causes**:
- Ceph pool not initialized
- Cinder-volume can't reach Ceph cluster
- Authentication failure

**Solutions**:
```bash
# Check Cinder logs on OpenStack node
ssh ubuntu@10.1.199.145
docker logs cinder_volume

# Common error: "client.cinder keyring not found"
# Verify keyring exists:
ls -la /etc/kolla/config/cinder/ceph.client.cinder.keyring

# Test Ceph connectivity from container
docker exec -it cinder_volume bash
ceph -s --conf /etc/ceph/ceph.conf --keyring /etc/ceph/ceph.client.cinder.keyring
# Should show cluster status

# If pool not initialized:
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rbd pool init volumes

# Verify pool exists
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep volumes
```

---

### Issue: Glance Image Upload Fails

**Symptoms**:
```
openstack image create --file cirros.img test
Failed to upload image data: Store glance.store.rbd.Store refused to upload image
```

**Causes**:
- Glance can't write to Ceph images pool
- Keyring permissions wrong

**Solutions**:
```bash
# Check Glance logs
ssh ubuntu@10.1.199.145
docker logs glance_api

# Verify Glance keyring permissions
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph auth get client.glance

# Should include: osd 'profile rbd pool=images'

# If wrong, recreate keyring:
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  ceph auth caps client.glance \
  mon 'profile rbd' \
  osd 'profile rbd pool=images' \
  mgr 'profile rbd pool=images'

# Copy to OpenStack
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph auth get client.glance \
  > /tmp/glance.keyring
scp /tmp/glance.keyring ubuntu@10.1.199.145:/etc/kolla/config/glance/ceph.client.glance.keyring

# Restart Glance
ssh ubuntu@10.1.199.145
docker restart glance_api
```

---

## Performance Issues

### Issue: Very Slow VM Performance in OpenStack

**Causes**:
- Nested virtualization overhead (VM in VM in VM)
- Ceph OSDs on slow virtual disks
- Insufficient RAM

**Solutions**:
```bash
# Enable nested virtualization on Proxmox host
cat /sys/module/kvm_intel/parameters/nested
# Should show: Y

# If N, enable:
echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-intel.conf
modprobe -r kvm_intel
modprobe kvm_intel

# Use virtio for VM disks (should be default)
# Check in Horizon: Instance flavor settings

# Increase OpenStack node RAM
qm set 4145 --memory 65536
qm set 4146 --memory 65536

# Tune Ceph for nested virtualization
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- bash
ceph config set osd osd_op_num_threads_per_shard 1
ceph config set osd osd_op_num_shards 2
```

---

## Cleanup & Recovery

### Complete Teardown

```bash
# On Proxmox host

# Stop all VMs
for i in {4140..4146}; do qm stop $i; done

# Destroy all VMs
for i in {4140..4146}; do qm destroy $i; done

# Remove template (optional)
qm destroy 4444

# Clean up config files (optional)
rm -f rook_ceph.conf pub_keys
```

---

### Partial Recovery: Restart OpenStack

```bash
# SSH to os0
ssh ubuntu@10.1.199.140

# Source credentials
source /etc/kolla/admin-openrc.sh

# List services
openstack compute service list
openstack network agent list

# Restart specific services
ssh ubuntu@10.1.199.145
docker restart nova_compute
docker restart neutron_openvswitch_agent
```

---

### Partial Recovery: Restart Rook-Ceph

```bash
# Delete and recreate Ceph cluster (data will be lost!)
kubectl delete -f ~/rook/deploy/examples/cluster.yaml
kubectl apply -f ~/rook/deploy/examples/cluster.yaml

# Wait for cluster to be ready
kubectl -n rook-ceph get cephcluster -w
```

---

## Log Locations

### Proxmox Host
- VM console: `qm terminal <vmid>`
- VM logs: `/var/log/pve/tasks/`

### VMs (os0-os6)
- Cloud-init: `/var/log/cloud-init.log`
- Syslog: `/var/log/syslog`
- Kubelet: `journalctl -u kubelet`

### Kubernetes (on os0)
- Pod logs: `kubectl logs -n <namespace> <pod-name>`
- Events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`

### Rook-Ceph
- Operator: `kubectl logs -n rook-ceph deploy/rook-ceph-operator`
- Ceph logs: `kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph log last 50`

### OpenStack (on os5/os6)
- Container logs: `docker logs <container-name>`
- Kolla logs: `/var/log/kolla/`
- Service logs (inside containers): `/var/log/kolla/<service>/`

---

## Getting Help

### Useful Commands

```bash
# Check all VMs status
qm list | grep 414

# Check all Kubernetes pods
kubectl get pods --all-namespaces

# Check all OpenStack services
source /etc/kolla/admin-openrc.sh
openstack catalog list
openstack compute service list
openstack network agent list

# Check Ceph health
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Check Docker status on OpenStack nodes
ssh ubuntu@10.1.199.145 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

### Community Resources

- **Kubespray Issues**: https://github.com/kubernetes-sigs/kubespray/issues
- **Rook Slack**: https://rook.io/slack
- **OpenStack IRC**: #openstack on OFTC
- **Kolla-Ansible Docs**: https://docs.openstack.org/kolla-ansible/latest/
- **Ceph Mailing List**: https://lists.ceph.io/

### Reporting Bugs

When reporting issues, include:
1. Output of failing command
2. Relevant log excerpts (with `--debug` or `-vvv` flags)
3. Your `rook_ceph.conf` settings (redact passwords)
4. Environment details (Proxmox version, VM resources, network topology)
5. Steps to reproduce
