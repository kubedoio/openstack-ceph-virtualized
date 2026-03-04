#!/usr/bin/env bash
###############################################################################
# Cloud Hypervisor Deployment Simulation
#
# This script simulates a complete deployment of the OpenStack-Ceph
# infrastructure on a bare metal Linux server with Cloud Hypervisor.
#
# Simulates:
# 1. Host setup (setup-cloud-hypervisor.sh)
# 2. VM creation (create-vm.sh)
# 3. Full deployment (deploy_rook_ceph.sh)
# 4. Verification steps
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Simulation settings
SIMULATE_DELAY=0.5
VERBOSE=true

###############################################################################
# Utility Functions
###############################################################################

log_info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

simulate_command() {
    local cmd="$1"
    local description="${2:-}"

    if [[ -n "$description" ]]; then
        log_info "$description"
    fi

    echo -e "${GREEN}\$ ${NC}${cmd}"
    sleep "$SIMULATE_DELAY"
}

simulate_output() {
    echo "$@"
    sleep "$SIMULATE_DELAY"
}

###############################################################################
# System Information
###############################################################################

show_system_info() {
    log_step "SIMULATION: Bare Metal Server with Cloud Hypervisor"

    cat <<EOF
Server Specifications:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hostname:        ch-host01.example.com
  OS:              Ubuntu 24.04 LTS (bare metal)
  Kernel:          6.8.0-45-generic
  CPU:             Intel Xeon E5-2690 v4 @ 2.60GHz (28 cores, 56 threads)
  RAM:             128 GB DDR4
  Storage:         2TB NVMe SSD
  Network:         2x 10GbE NICs (ens1f0, ens1f1)
  Virtualization:  KVM enabled (Intel VT-x)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current State:
  - Fresh Ubuntu 24.04 installation
  - Root access available
  - Internet connectivity: OK
  - No hypervisor installed yet

EOF
    sleep 2
}

###############################################################################
# Phase 1: Host Setup
###############################################################################

phase1_host_setup() {
    log_step "PHASE 1: Cloud Hypervisor Host Setup"

    simulate_command "sudo ./setup-cloud-hypervisor.sh" \
        "Running Cloud Hypervisor setup script..."

    echo ""
    simulate_output "==================================="
    simulate_output "Cloud Hypervisor Host Setup"
    simulate_output "==================================="
    simulate_output "Operating System: ubuntu 24.04"
    simulate_output "Internal Bridge:  chbr1199 (10.1.199.254/24)"
    simulate_output "External Bridge:  chbr2199 (10.2.199.254/24)"
    simulate_output "==================================="
    simulate_output ""

    # Step 1: Package installation
    simulate_output "Step 1: Installing required packages..."
    simulate_command "apt-get update" ""
    simulate_output "Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease"
    simulate_output "Get:2 http://archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]"
    simulate_output "Fetched 8,234 kB in 3s (2,745 kB/s)"
    simulate_output "Reading package lists... Done"

    simulate_command "apt-get install -y qemu-utils genisoimage bridge-utils iproute2 iptables curl wget jq socat" ""
    simulate_output "Reading package lists... Done"
    simulate_output "Building dependency tree... Done"
    simulate_output "The following NEW packages will be installed:"
    simulate_output "  qemu-utils genisoimage bridge-utils iproute2 iptables curl wget jq socat"
    simulate_output "0 upgraded, 9 newly installed, 0 to remove and 0 not upgraded."
    simulate_output "Need to get 12.4 MB of archives."
    simulate_output "After this operation, 45.2 MB of additional disk space will be used."
    simulate_output "Fetching packages..."
    sleep 1
    simulate_output "Unpacking qemu-utils (1:8.2.2+ds-0ubuntu1) ..."
    simulate_output "Setting up qemu-utils (1:8.2.2+ds-0ubuntu1) ..."
    simulate_output "Setting up genisoimage (9:1.1.11-3.4ubuntu1) ..."
    log_success "Packages installed successfully"
    simulate_output ""

    # Step 2: Cloud Hypervisor installation
    simulate_output "Step 2: Installing Cloud Hypervisor..."
    simulate_command "curl -L -o /tmp/cloud-hypervisor https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/v42.0/cloud-hypervisor-static" \
        "Downloading Cloud Hypervisor v42.0..."
    simulate_output "  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current"
    simulate_output "                                 Dload  Upload   Total   Spent    Left  Speed"
    simulate_output "100 15.2M  100 15.2M    0     0  8234k      0  0:00:01  0:00:01 --:--:-- 8234k"

    simulate_command "curl -L -o /tmp/ch-remote https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/v42.0/ch-remote-static" ""
    simulate_output "100  3.4M  100  3.4M    0     0  7123k      0  0:00:00  0:00:00 --:--:-- 7123k"

    simulate_command "install -m 755 /tmp/cloud-hypervisor /usr/local/bin/cloud-hypervisor" ""
    simulate_command "install -m 755 /tmp/ch-remote /usr/local/bin/ch-remote" ""

    simulate_command "cloud-hypervisor --version" "Verifying installation..."
    simulate_output "cloud-hypervisor v42.0"
    log_success "Cloud Hypervisor installed: cloud-hypervisor v42.0"
    simulate_output ""

    # Step 3: Directory creation
    simulate_output "Step 3: Creating directories..."
    simulate_command "mkdir -p /var/lib/cloud-hypervisor/vms" ""
    simulate_command "mkdir -p /var/lib/cloud-hypervisor/images" ""
    simulate_command "mkdir -p /run/cloud-hypervisor" ""
    log_success "Directories created:"
    simulate_output "  - VMs:    /var/lib/cloud-hypervisor/vms"
    simulate_output "  - Images: /var/lib/cloud-hypervisor/images"
    simulate_output "  - Sockets: /run/cloud-hypervisor"
    simulate_output ""

    # Step 4: Network bridge setup
    simulate_output "Step 4: Setting up network bridges..."
    simulate_command "ip link add chbr1199 type bridge" "Creating internal bridge (chbr1199)..."
    simulate_command "ip addr add 10.1.199.254/24 dev chbr1199" ""
    simulate_command "ip link set chbr1199 up" ""
    log_success "Bridge chbr1199 created successfully"

    simulate_command "ip link add chbr2199 type bridge" "Creating external bridge (chbr2199)..."
    simulate_command "ip addr add 10.2.199.254/24 dev chbr2199" ""
    simulate_command "ip link set chbr2199 up" ""
    log_success "Bridge chbr2199 created successfully"

    simulate_command "sysctl -w net.ipv4.ip_forward=1" "Enabling IP forwarding..."
    simulate_output "net.ipv4.ip_forward = 1"

    simulate_command "iptables -t nat -A POSTROUTING -s 10.2.199.0/24 -o ens1f0 -j MASQUERADE" "Setting up NAT..."
    log_success "Network bridges configured successfully"
    simulate_output ""

    # Step 5: Persistent configuration
    simulate_output "Step 5: Making bridge configuration persistent..."
    simulate_command "cat > /etc/systemd/system/cloudhypervisor-bridges.service <<EOF" ""
    simulate_output "[Unit]"
    simulate_output "Description=Cloud Hypervisor Network Bridges"
    simulate_output "After=network.target"
    simulate_output ""
    simulate_output "[Service]"
    simulate_output "Type=oneshot"
    simulate_output "RemainAfterExit=yes"
    simulate_output "ExecStart=/bin/bash -c 'source lib/common/network.sh && setup_cloudhypervisor_network'"
    simulate_output ""
    simulate_output "[Install]"
    simulate_output "WantedBy=multi-user.target"
    simulate_output "EOF"

    simulate_command "systemctl daemon-reload" ""
    simulate_command "systemctl enable cloudhypervisor-bridges.service" ""
    simulate_output "Created symlink /etc/systemd/system/multi-user.target.wants/cloudhypervisor-bridges.service"
    log_success "Bridge configuration will persist across reboots"
    simulate_output ""

    # Step 6: Firewall configuration
    simulate_output "Step 6: Configuring firewall..."
    simulate_command "ufw status" "Checking firewall status..."
    simulate_output "Status: active"

    simulate_command "ufw allow in on chbr1199" ""
    simulate_output "Rule added"
    simulate_command "ufw allow in on chbr2199" ""
    simulate_output "Rule added"
    log_success "UFW rules added"
    simulate_output ""

    # Step 7: Download Ubuntu cloud image
    simulate_output "Step 7: Downloading Ubuntu cloud image template..."
    simulate_command "curl -L -o /var/lib/cloud-hypervisor/images/ubuntu-24.04-cloudimg.qcow2 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" \
        "Downloading Ubuntu 24.04 cloud image..."
    simulate_output "  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current"
    simulate_output "                                 Dload  Upload   Total   Spent    Left  Speed"
    simulate_output "100  627M  100  627M    0     0  42.1M      0  0:00:14  0:00:14 --:--:-- 45.2M"

    simulate_command "qemu-img convert -f qcow2 -O raw /var/lib/cloud-hypervisor/images/ubuntu-24.04-cloudimg.qcow2 /var/lib/cloud-hypervisor/images/template-4444.raw" \
        "Converting to raw format..."
    simulate_output "Converting image... 100%"
    log_success "Template created: /var/lib/cloud-hypervisor/images/template-4444.raw"
    simulate_output ""

    # Step 8: Verification
    simulate_output "Step 8: Verifying installation..."

    local errors=0

    simulate_command "command -v cloud-hypervisor" ""
    simulate_output "/usr/local/bin/cloud-hypervisor"

    simulate_command "command -v ch-remote" ""
    simulate_output "/usr/local/bin/ch-remote"

    simulate_command "ip link show chbr1199" ""
    simulate_output "5: chbr1199: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default"
    simulate_output "    link/ether 02:42:ac:11:00:01 brd ff:ff:ff:ff:ff:ff"

    simulate_command "ip link show chbr2199" ""
    simulate_output "6: chbr2199: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default"
    simulate_output "    link/ether 02:42:ac:12:00:01 brd ff:ff:ff:ff:ff:ff"

    simulate_command "cat /proc/sys/net/ipv4/ip_forward" ""
    simulate_output "1"

    simulate_command "ls -lh /var/lib/cloud-hypervisor/images/template-4444.raw" ""
    simulate_output "-rw-r--r-- 1 root root 2.2G Mar  4 10:45 /var/lib/cloud-hypervisor/images/template-4444.raw"

    echo ""
    log_success "✓ Setup completed successfully!"
    simulate_output "==================================="
    simulate_output ""
    simulate_output "Cloud Hypervisor host is ready for VM deployment."
    simulate_output ""
    simulate_output "Network bridges:"
    simulate_output "  - Internal: chbr1199 (10.1.199.254/24)"
    simulate_output "  - External: chbr2199 (10.2.199.254/24)"
    simulate_output ""
    simulate_output "Template: /var/lib/cloud-hypervisor/images/template-4444.raw"
    simulate_output "==================================="

    sleep 2
}

###############################################################################
# Phase 2: Single VM Test
###############################################################################

phase2_single_vm_test() {
    log_step "PHASE 2: Single VM Creation Test"

    log_info "Creating SSH key for VMs..."
    simulate_command "cat ~/.ssh/id_rsa.pub > pub_keys" ""
    simulate_output "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... user@ch-host01"
    log_success "SSH key added to pub_keys"
    simulate_output ""

    log_info "Creating test VM (os1)..."
    simulate_command "./create-vm.sh 4444 4141 os1.cluster.local 10.1.199.141/24 10.1.199.254" \
        "Creating VM with abstraction layer..."

    simulate_output "==================================="
    simulate_output "Creating VM with Hypervisor Abstraction"
    simulate_output "==================================="
    simulate_output "VM ID:        4141"
    simulate_output "VM Name:      os1.cluster.local"
    simulate_output "IP/CIDR:      10.1.199.141/24"
    simulate_output "Gateway:      10.1.199.254"
    simulate_output "Template ID:  4444"
    simulate_output "==================================="
    simulate_output ""

    simulate_output "INFO: Using hypervisor: cloudhypervisor"
    simulate_output ""

    simulate_output "Step 1: Cloning template 4444 to VM 4141..."
    simulate_output "INFO: Cloning template 4444 to VM 4141"
    simulate_output "INFO: Cloning template disk as VM's system disk"
    simulate_output "INFO: Converting qcow2 template to raw format"
    sleep 1
    simulate_output "INFO: Resizing disk to 50GB"
    simulate_output "Image resized."
    log_success "Template cloned successfully"
    simulate_output ""

    simulate_output "Step 2: Configuring VM resources..."
    simulate_output "INFO: Setting CPU cores to 4"
    simulate_output "INFO: Setting memory to 8192MB"
    log_success "Resources configured"
    simulate_output ""

    simulate_output "Step 3: Configuring cloud-init..."
    simulate_output "INFO: Generating cloud-init NoCloud ISO"
    simulate_output "INFO: Cloud-init ISO created: /var/lib/cloud-hypervisor/vms/vm-4141/cloudinit.iso"
    log_success "Cloud-init configured"
    simulate_output ""

    simulate_output "Step 4: Resizing system disk..."
    simulate_output "INFO: Resizing disk scsi0 (+25GB)"
    simulate_output "Image resized."
    log_success "System disk resized"
    simulate_output ""

    simulate_output "Step 5: Adding OSD disks for Ceph..."
    simulate_output "INFO: Creating raw disk: /var/lib/cloud-hypervisor/vms/vm-4141/disk-1.raw (100GB, sparse)"
    simulate_output "INFO: Raw disk created: /var/lib/cloud-hypervisor/vms/vm-4141/disk-1.raw"
    simulate_output "INFO: Disk added to VM 4141: /var/lib/cloud-hypervisor/vms/vm-4141/disk-1.raw (100GB)"

    simulate_output "INFO: Creating raw disk: /var/lib/cloud-hypervisor/vms/vm-4141/disk-2.raw (100GB, sparse)"
    simulate_output "INFO: Raw disk created: /var/lib/cloud-hypervisor/vms/vm-4141/disk-2.raw"
    simulate_output "INFO: Disk added to VM 4141: /var/lib/cloud-hypervisor/vms/vm-4141/disk-2.raw (100GB)"
    log_success "OSD disks added"
    simulate_output ""

    simulate_output "Step 6: Configuring network interfaces..."
    simulate_output "INFO: Creating TAP device: tap-4141-0 on bridge chbr1199"
    simulate_output "INFO: TAP device tap-4141-0 created and attached to chbr1199"
    simulate_output "INFO: Network interface added to VM 4141 (bridge: chbr1199, tap: tap-4141-0)"

    simulate_output "INFO: Creating TAP device: tap-4141-1 on bridge chbr2199"
    simulate_output "INFO: TAP device tap-4141-1 created and attached to chbr2199"
    simulate_output "INFO: Network interface added to VM 4141 (bridge: chbr2199, tap: tap-4141-1)"
    log_success "Network interfaces configured"
    simulate_output ""

    simulate_output "==================================="
    simulate_output "VM Created Successfully!"
    simulate_output "==================================="
    simulate_output "VM ID:        4141"
    simulate_output "VM Name:      os1.cluster.local"
    simulate_output "IP Address:   10.1.199.141/24"
    simulate_output "Cores:        4"
    simulate_output "Memory:       8192MB"
    simulate_output "OSD Disks:    2 x 100GB"
    simulate_output "Hypervisor:   cloudhypervisor"
    simulate_output ""
    simulate_output "To start the VM, run:"
    simulate_output "  hv_start_vm 4141"
    simulate_output ""
    simulate_output "Note: The VM is NOT started automatically."
    simulate_output "==================================="

    sleep 2

    # Start the VM
    log_info "Starting VM 4141..."
    simulate_command "source lib/hypervisor.sh && hv_init && hv_start_vm 4141" ""

    simulate_output "INFO: Using hypervisor: cloudhypervisor"
    simulate_output "INFO: Starting VM 4141 with Cloud Hypervisor"
    simulate_output "INFO: Ensuring TAP device tap-4141-0 exists"
    simulate_output "INFO: TAP device tap-4141-0 already exists"
    simulate_output "INFO: Ensuring TAP device tap-4141-1 exists"
    simulate_output "INFO: TAP device tap-4141-1 already exists"
    sleep 1
    simulate_output "INFO: VM 4141 started (PID: 12847)"
    log_success "VM 4141 is now running"
    simulate_output ""

    # Check VM status
    log_info "Checking VM status..."
    simulate_command "hv_vm_status 4141" ""
    simulate_output "running"
    simulate_output ""

    # Wait for cloud-init
    log_info "Waiting for cloud-init to complete (30 seconds)..."
    for i in {1..6}; do
        echo -n "."
        sleep 0.3
    done
    echo ""
    log_success "Cloud-init should be complete"
    simulate_output ""

    # Test SSH connection
    log_info "Testing SSH connection to VM..."
    simulate_command "ssh -o StrictHostKeyChecking=no ubuntu@10.1.199.141 'hostname'" ""
    simulate_output "Warning: Permanently added '10.1.199.141' (ED25519) to the list of known hosts."
    simulate_output "os1"
    log_success "SSH connection successful!"
    simulate_output ""

    # Check VM internals
    log_info "Checking VM configuration..."
    simulate_command "ssh ubuntu@10.1.199.141 'ip addr show eth0'" ""
    simulate_output "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000"
    simulate_output "    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff"
    simulate_output "    inet 10.1.199.141/24 brd 10.1.199.255 scope global eth0"
    simulate_output "       valid_lft forever preferred_lft forever"

    simulate_command "ssh ubuntu@10.1.199.141 'ip addr show ens19'" ""
    simulate_output "3: ens19: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000"
    simulate_output "    link/ether 52:54:00:ab:cd:ef brd ff:ff:ff:ff:ff:ff"

    simulate_command "ssh ubuntu@10.1.199.141 'lsblk'" ""
    simulate_output "NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS"
    simulate_output "sda      8:0    0   50G  0 disk"
    simulate_output "├─sda1   8:1    0 49.9G  0 part /"
    simulate_output "├─sda14  8:14   0    4M  0 part"
    simulate_output "└─sda15  8:15   0  106M  0 part /boot/efi"
    simulate_output "sdb      8:16   0  100G  0 disk"
    simulate_output "sdc      8:32   0  100G  0 disk"

    log_success "VM 4141 is fully operational!"
    log_success "✓ Network interfaces: eth0 (10.1.199.141), ens19"
    log_success "✓ Disks: sda (50GB system), sdb (100GB OSD), sdc (100GB OSD)"

    sleep 2
}

###############################################################################
# Phase 3: Full Deployment
###############################################################################

phase3_full_deployment() {
    log_step "PHASE 3: Full 7-VM Cluster Deployment"

    log_info "Starting full deployment..."
    simulate_command "./deploy_rook_ceph.sh" \
        "Running Rook-Ceph deployment script..."

    simulate_output "INFO: Using hypervisor: cloudhypervisor"
    simulate_output "INFO: Setting up Cloud Hypervisor network infrastructure..."
    simulate_output "INFO: Bridge chbr1199 already exists"
    simulate_output "INFO: Bridge chbr2199 already exists"
    simulate_output "INFO: IP forwarding enabled"
    simulate_output ""

    simulate_output "    Using config from rook_ceph.conf"
    simulate_output "    Jump host VM-ID : 4140  (10.1.199.140)"
    simulate_output "    Worker VMs      : 6  (IDs 4141-4146)"
    simulate_output "    Template ID     : 4444"
    simulate_output "    Gateway         : 10.1.199.254"
    simulate_output ""

    # Create jump host (os0)
    simulate_output "Creating jump host (os0)…"
    simulate_command "./create-vm.sh 4444 4140 os0.cluster.local 10.1.199.140/24 10.1.199.254" ""
    sleep 0.5
    simulate_output "INFO: Using hypervisor: cloudhypervisor"
    simulate_output "INFO: Cloning template 4444 to VM 4140"
    simulate_output "INFO: VM 4140 created (not started)"
    simulate_output "==================================="
    simulate_output "VM Created Successfully!"
    simulate_output "==================================="
    simulate_output ""

    simulate_command "hv_start_vm 4140" "Starting jump host (os0)..."
    simulate_output "INFO: Starting VM 4140 with Cloud Hypervisor"
    simulate_output "INFO: VM 4140 started (PID: 13201)"

    log_info "Waiting for cloud-init (20 seconds)..."
    for i in {1..4}; do
        echo -n "."
        sleep 0.3
    done
    echo ""
    simulate_output ""

    simulate_output "Generating SSH key on os0 and collecting it locally…"
    simulate_command "ssh ubuntu@10.1.199.140 'ssh-keygen -q -t rsa -N \"\" -f ~/.ssh/id_rsa <<<y'" ""
    simulate_output "Generating public/private rsa key pair."
    simulate_output "Your identification has been saved in /home/ubuntu/.ssh/id_rsa"
    simulate_output "Your public key has been saved in /home/ubuntu/.ssh/id_rsa.pub"

    simulate_command "ssh ubuntu@10.1.199.140 'cat ~/.ssh/id_rsa.pub' >> pub_keys" ""
    log_success "SSH key collected from os0"
    simulate_output ""

    # Create worker VMs
    simulate_output "Creating worker VMs (os1…os6)…"

    for i in {1..6}; do
        local vm_id=$((4140 + i))
        local ip_suffix=$((140 + i))
        local hostname="os${i}.cluster.local"
        local ip="10.1.199.${ip_suffix}"

        log_info "Creating $hostname (VM $vm_id)..."
        simulate_command "./create-vm.sh 4444 $vm_id $hostname ${ip}/24 10.1.199.254" ""
        sleep 0.3
        simulate_output "INFO: Cloning template 4444 to VM $vm_id"
        simulate_output "INFO: VM $vm_id created"
        log_success "VM $vm_id ($hostname) created"
    done
    simulate_output ""

    # Bump RAM for OpenStack nodes
    simulate_output "Setting os5 (VM-ID 4145) memory to 32768 MiB"
    simulate_command "hv_set_memory 4145 32768" ""
    simulate_output "Setting os6 (VM-ID 4146) memory to 32768 MiB"
    simulate_command "hv_set_memory 4146 32768" ""
    log_success "OpenStack node memory increased to 32GB"
    simulate_output ""

    # Boot all VMs
    simulate_output "Booting all worker VMs…"
    for i in {1..6}; do
        local vm_id=$((4140 + i))
        simulate_command "hv_start_vm $vm_id" "Starting VM $vm_id..."
        sleep 0.2
        simulate_output "INFO: VM $vm_id started (PID: $((13300 + i)))"
    done
    log_success "All 7 VMs are running"
    simulate_output ""

    # Show VM status
    log_info "Checking VM status..."
    simulate_command "ps aux | grep cloud-hypervisor | grep -v grep | wc -l" ""
    simulate_output "7"
    log_success "7 Cloud Hypervisor processes running"
    simulate_output ""

    simulate_command "ip tuntap list | grep tap-41 | wc -l" ""
    simulate_output "14"
    log_success "14 TAP devices created (2 per VM)"
    simulate_output ""

    sleep 2

    # Kubespray deployment
    log_step "Deploying Kubernetes with Kubespray"

    simulate_output "Copying config & deployer to os0…"
    simulate_command "scp rook_ceph.conf ubuntu@10.1.199.140:/home/ubuntu/" ""
    simulate_output "rook_ceph.conf                           100% 2134   2.1MB/s   00:00"

    simulate_command "scp /tmp/rook-ceph-deploy.sh ubuntu@10.1.199.140:/home/ubuntu/" ""
    simulate_output "rook-ceph-deploy.sh                      100% 8234   8.0MB/s   00:00"
    simulate_output ""

    log_info "Running remote deployment script on os0..."
    simulate_output "Connecting to ubuntu@10.1.199.140..."
    simulate_output ""

    simulate_output "=========================================="
    simulate_output "Remote Deployment on os0 (Jump Host)"
    simulate_output "=========================================="
    simulate_output ""

    simulate_output "Installing kubectl, Git, Python tooling…"
    simulate_command "sudo apt update && sudo apt install -y git python3-venv python3-pip jq curl" ""
    simulate_output "Hit:1 http://ports.ubuntu.com/ubuntu-ports noble InRelease"
    simulate_output "Reading package lists... Done"
    simulate_output "git is already the newest version (1:2.43.0-1ubuntu7)"
    simulate_output "python3-venv is already the newest version (3.12.3-0ubuntu1)"
    sleep 1
    log_success "System packages installed"
    simulate_output ""

    simulate_output "Downloading kubectl..."
    simulate_command "curl -LO \"https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl\"" ""
    simulate_output "  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current"
    simulate_output "                                 Dload  Upload   Total   Spent    Left  Speed"
    simulate_output "100 49.0M  100 49.0M    0     0  15.2M      0  0:00:03  0:00:03 --:--:-- 15.2M"

    simulate_command "chmod +x kubectl && sudo mv kubectl /usr/local/bin" ""
    simulate_command "kubectl version --client" ""
    simulate_output "Client Version: v1.31.0"
    log_success "kubectl installed"
    simulate_output ""

    simulate_output "Cloning Kubespray..."
    simulate_command "git clone https://github.com/kubernetes-sigs/kubespray.git" ""
    simulate_output "Cloning into 'kubespray'..."
    simulate_output "remote: Enumerating objects: 82145, done."
    simulate_output "remote: Counting objects: 100% (82145/82145), done."
    simulate_output "remote: Total 82145 (delta 0), reused 0 (delta 0), pack-reused 0"
    simulate_output "Receiving objects: 100% (82145/82145), 24.32 MiB | 18.45 MiB/s, done."
    simulate_output "Resolving deltas: 100% (46234/46234), done."
    log_success "Kubespray cloned"
    simulate_output ""

    simulate_output "Setting up Kubespray environment..."
    simulate_command "cd kubespray && python3 -m venv .venv" ""
    simulate_command "source .venv/bin/activate && pip install -U -r requirements.txt" ""
    simulate_output "Collecting ansible-core>=2.16"
    simulate_output "  Downloading ansible_core-2.17.5-py3-none-any.whl (2.2 MB)"
    sleep 1
    simulate_output "Successfully installed ansible-core-2.17.5 jinja2-3.1.4 MarkupSafe-2.1.5"
    log_success "Python environment ready"
    simulate_output ""

    simulate_output "Creating inventory for 4-node cluster..."
    simulate_command "cp -rfp inventory/sample inventory/rook-ceph-k8s" ""

    simulate_output "Generating hosts.yaml..."
    simulate_output "all:"
    simulate_output "  hosts:"
    simulate_output "    os1:"
    simulate_output "      ansible_host: 10.1.199.141"
    simulate_output "      ip: 10.1.199.141"
    simulate_output "    os2:"
    simulate_output "      ansible_host: 10.1.199.142"
    simulate_output "      ip: 10.1.199.142"
    simulate_output "    os3:"
    simulate_output "      ansible_host: 10.1.199.143"
    simulate_output "      ip: 10.1.199.143"
    simulate_output "    os4:"
    simulate_output "      ansible_host: 10.1.199.144"
    simulate_output "      ip: 10.1.199.144"
    simulate_output "  children:"
    simulate_output "    kube_control_plane:"
    simulate_output "      hosts:"
    simulate_output "        os1:"
    simulate_output "    kube_node:"
    simulate_output "      hosts:"
    simulate_output "        os1:"
    simulate_output "        os2:"
    simulate_output "        os3:"
    simulate_output "        os4:"
    simulate_output "    etcd:"
    simulate_output "      hosts:"
    simulate_output "        os1:"
    simulate_output "        os2:"
    simulate_output "        os3:"
    log_success "Inventory created"
    simulate_output ""

    log_info "Running Ansible playbook (this takes 15-20 minutes)..."
    simulate_command "ansible-playbook -i inventory/rook-ceph-k8s/hosts.yaml cluster.yml" ""
    simulate_output ""
    simulate_output "PLAY [Check Ansible version] *******************************************"
    simulate_output ""
    simulate_output "TASK [Check ansible_version] *******************************************"
    simulate_output "ok: [localhost]"
    simulate_output ""
    simulate_output "PLAY [Gather facts] ****************************************************"
    sleep 0.5
    simulate_output ""
    simulate_output "TASK [Gathering Facts] *************************************************"
    simulate_output "ok: [os1]"
    simulate_output "ok: [os2]"
    simulate_output "ok: [os3]"
    simulate_output "ok: [os4]"
    sleep 0.5
    simulate_output ""
    simulate_output "PLAY [Download files / images] *****************************************"
    simulate_output ""
    simulate_output "TASK [download : Download files / images] ******************************"
    simulate_output "included: /home/ubuntu/kubespray/roles/download/tasks/download_container.yml"
    sleep 0.5

    log_info "Installing Kubernetes components..."
    for i in {1..5}; do
        echo -n "."
        sleep 0.4
    done
    echo ""

    simulate_output ""
    simulate_output "PLAY [Set up container engine] *****************************************"
    simulate_output "ok: [os1] => (item=containerd)"
    simulate_output "ok: [os2] => (item=containerd)"
    simulate_output "ok: [os3] => (item=containerd)"
    simulate_output "ok: [os4] => (item=containerd)"
    simulate_output ""
    sleep 0.5

    simulate_output "PLAY [Set up Kubernetes control plane] *********************************"
    simulate_output "changed: [os1] => (item=kubeadm init)"
    simulate_output "ok: [os1] => (item=kubectl)"
    sleep 0.5

    simulate_output ""
    simulate_output "PLAY [Join Kubernetes nodes] *******************************************"
    simulate_output "changed: [os2] => (item=kubeadm join)"
    simulate_output "changed: [os3] => (item=kubeadm join)"
    simulate_output "changed: [os4] => (item=kubeadm join)"
    sleep 0.5

    simulate_output ""
    simulate_output "PLAY [Configure kubectl] ***********************************************"
    simulate_output "ok: [os1]"
    simulate_output ""
    simulate_output "PLAY RECAP *************************************************************"
    simulate_output "os1                        : ok=423  changed=78   unreachable=0    failed=0    skipped=245  rescued=0    ignored=1"
    simulate_output "os2                        : ok=289  changed=56   unreachable=0    failed=0    skipped=198  rescued=0    ignored=1"
    simulate_output "os3                        : ok=289  changed=56   unreachable=0    failed=0    skipped=198  rescued=0    ignored=1"
    simulate_output "os4                        : ok=289  changed=56   unreachable=0    failed=0    skipped=198  rescued=0    ignored=1"
    simulate_output ""
    log_success "Kubernetes cluster deployed successfully!"
    simulate_output ""

    sleep 2
}

###############################################################################
# Phase 4: Rook-Ceph Deployment
###############################################################################

phase4_rook_ceph_deployment() {
    log_step "PHASE 4: Rook-Ceph Deployment"

    log_info "Deploying Rook-Ceph operator..."
    simulate_command "kubectl apply -f kubespray/rook/crds.yaml" ""
    simulate_output "customresourcedefinition.apiextensions.k8s.io/cephblockpools.ceph.rook.io created"
    simulate_output "customresourcedefinition.apiextensions.k8s.io/cephclusters.ceph.rook.io created"
    simulate_output "customresourcedefinition.apiextensions.k8s.io/cephfilesystems.ceph.rook.io created"
    simulate_output "customresourcedefinition.apiextensions.k8s.io/cephobjectstores.ceph.rook.io created"

    simulate_command "kubectl apply -f kubespray/rook/common.yaml" ""
    simulate_output "namespace/rook-ceph created"
    simulate_output "serviceaccount/rook-ceph-operator created"
    simulate_output "clusterrole.rbac.authorization.k8s.io/rook-ceph-operator created"

    simulate_command "kubectl apply -f kubespray/rook/operator.yaml" ""
    simulate_output "deployment.apps/rook-ceph-operator created"
    simulate_output ""

    log_info "Waiting for Rook operator to be ready..."
    simulate_command "kubectl -n rook-ceph get pods" ""
    simulate_output "NAME                                  READY   STATUS    RESTARTS   AGE"
    simulate_output "rook-ceph-operator-7c8c9d8b9c-xk2zp   0/1     Running   0          15s"

    for i in {1..4}; do
        echo -n "."
        sleep 0.5
    done
    echo ""

    simulate_command "kubectl -n rook-ceph get pods" ""
    simulate_output "NAME                                  READY   STATUS    RESTARTS   AGE"
    simulate_output "rook-ceph-operator-7c8c9d8b9c-xk2zp   1/1     Running   0          45s"
    log_success "Rook operator is ready"
    simulate_output ""

    log_info "Deploying Ceph cluster..."
    simulate_command "kubectl apply -f kubespray/rook/cluster.yaml" ""
    simulate_output "cephcluster.ceph.rook.io/rook-ceph created"
    simulate_output ""

    log_info "Waiting for Ceph cluster to be ready (this takes 5-10 minutes)..."
    simulate_output "Ceph will discover and configure OSD disks on os1, os2, os3, os4..."
    simulate_output ""

    for i in {1..8}; do
        echo -n "."
        sleep 0.5
    done
    echo ""

    simulate_command "kubectl -n rook-ceph get pods" ""
    simulate_output "NAME                                            READY   STATUS      RESTARTS   AGE"
    simulate_output "rook-ceph-operator-7c8c9d8b9c-xk2zp             1/1     Running     0          5m23s"
    simulate_output "rook-ceph-mon-a-5c9f8d7b9c-qw7rt                1/1     Running     0          3m12s"
    simulate_output "rook-ceph-mon-b-7d8e9f2c4d-xs9pq                1/1     Running     0          2m45s"
    simulate_output "rook-ceph-mon-c-8e9f2d3c5e-zt2vr                1/1     Running     0          2m18s"
    simulate_output "rook-ceph-mgr-a-9f2e3d4c6f-ab4ws                1/1     Running     0          1m56s"
    simulate_output "rook-ceph-osd-0-5c6d7e8f9a-bc5xt                1/1     Running     0          1m34s"
    simulate_output "rook-ceph-osd-1-6d7e8f9a0b-cd6yu                1/1     Running     0          1m28s"
    simulate_output "rook-ceph-osd-2-7e8f9a0b1c-de7zv                1/1     Running     0          1m22s"
    simulate_output "rook-ceph-osd-3-8f9a0b1c2d-ef8aw                1/1     Running     0          1m16s"
    simulate_output "rook-ceph-osd-4-9a0b1c2d3e-fg9bx                1/1     Running     0          1m10s"
    simulate_output "rook-ceph-osd-5-0b1c2d3e4f-gh0cy                1/1     Running     0          1m04s"
    simulate_output "rook-ceph-osd-6-1c2d3e4f5g-hi1dz                1/1     Running     0          58s"
    simulate_output "rook-ceph-osd-7-2d3e4f5g6h-ij2ea                1/1     Running     0          52s"
    simulate_output "rook-ceph-tools-5d8f9b2c3a-jk3fb                1/1     Running     0          45s"
    simulate_output ""
    log_success "All Ceph pods are running!"
    simulate_output ""

    log_info "Checking Ceph cluster health..."
    simulate_command "kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s" ""
    simulate_output "  cluster:"
    simulate_output "    id:     a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    simulate_output "    health: HEALTH_OK"
    simulate_output ""
    simulate_output "  services:"
    simulate_output "    mon: 3 daemons, quorum a,b,c (age 4m)"
    simulate_output "    mgr: a(active, since 3m)"
    simulate_output "    osd: 8 osds: 8 up (since 2m), 8 in (since 2m)"
    simulate_output ""
    simulate_output "  data:"
    simulate_output "    pools:   1 pools, 32 pgs"
    simulate_output "    objects: 0 objects, 0 B"
    simulate_output "    usage:   8.1 GiB used, 792 GiB / 800 GiB avail"
    simulate_output "    pgs:     32 active+clean"
    simulate_output ""
    log_success "✓ Ceph cluster is HEALTH_OK"
    log_success "✓ 8 OSDs running (2 disks × 4 nodes)"
    log_success "✓ 800GB total storage available"
    simulate_output ""

    sleep 2
}

###############################################################################
# Phase 5: Verification
###############################################################################

phase5_verification() {
    log_step "PHASE 5: Cluster Verification"

    log_info "Verifying Kubernetes cluster..."
    simulate_command "kubectl get nodes -o wide" ""
    simulate_output "NAME   STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME"
    simulate_output "os1    Ready    control-plane   12m     v1.31.0   10.1.199.141    <none>        Ubuntu 24.04 LTS     6.8.0-45-generic    containerd://1.7.22"
    simulate_output "os2    Ready    <none>          11m     v1.31.0   10.1.199.142    <none>        Ubuntu 24.04 LTS     6.8.0-45-generic    containerd://1.7.22"
    simulate_output "os3    Ready    <none>          11m     v1.31.0   10.1.199.143    <none>        Ubuntu 24.04 LTS     6.8.0-45-generic    containerd://1.7.22"
    simulate_output "os4    Ready    <none>          11m     v1.31.0   10.1.199.144    <none>        Ubuntu 24.04 LTS     6.8.0-45-generic    containerd://1.7.22"
    log_success "✓ All 4 Kubernetes nodes are Ready"
    simulate_output ""

    log_info "Verifying system pods..."
    simulate_command "kubectl get pods -n kube-system" ""
    simulate_output "NAME                          READY   STATUS    RESTARTS   AGE"
    simulate_output "coredns-5d78c9869d-abc12      1/1     Running   0          11m"
    simulate_output "coredns-5d78c9869d-def34      1/1     Running   0          11m"
    simulate_output "kube-apiserver-os1            1/1     Running   0          12m"
    simulate_output "kube-controller-manager-os1   1/1     Running   0          12m"
    simulate_output "kube-proxy-ghi56              1/1     Running   0          11m"
    simulate_output "kube-proxy-jkl78              1/1     Running   0          11m"
    simulate_output "kube-proxy-mno90              1/1     Running   0          11m"
    simulate_output "kube-proxy-pqr12              1/1     Running   0          11m"
    simulate_output "kube-scheduler-os1            1/1     Running   0          12m"
    log_success "✓ All system pods are Running"
    simulate_output ""

    log_info "Verifying Rook-Ceph resources..."
    simulate_command "kubectl -n rook-ceph get cephcluster" ""
    simulate_output "NAME        DATADIRHOSTPATH   MONCOUNT   AGE     PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID"
    simulate_output "rook-ceph   /var/lib/rook     3          8m12s   Ready   Cluster created successfully   HEALTH_OK              a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    log_success "✓ Ceph cluster is Ready and Healthy"
    simulate_output ""

    log_info "Verifying storage class..."
    simulate_command "kubectl get storageclass" ""
    simulate_output "NAME              PROVISIONER                  RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE"
    simulate_output "rook-ceph-block   rook-ceph.rbd.csi.ceph.com   Delete          Immediate           true                   7m45s"
    log_success "✓ Storage class available"
    simulate_output ""

    log_info "Testing storage with PVC..."
    simulate_command "kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: rook-ceph-block
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF" ""
    simulate_output "persistentvolumeclaim/test-pvc created"

    sleep 1

    simulate_command "kubectl get pvc test-pvc" ""
    simulate_output "NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE"
    simulate_output "test-pvc   Bound    pvc-1234abcd-5678-90ef-ghij-klmnopqrstuv   1Gi        RWO            rook-ceph-block   5s"
    log_success "✓ PVC successfully bound to Ceph volume"
    simulate_output ""

    simulate_command "kubectl delete pvc test-pvc" ""
    simulate_output "persistentvolumeclaim \"test-pvc\" deleted"
    simulate_output ""

    log_info "Checking host resources..."
    simulate_command "free -h" ""
    simulate_output "               total        used        free      shared  buff/cache   available"
    simulate_output "Mem:           126Gi        42Gi        68Gi       2.1Gi        16Gi        82Gi"
    simulate_output "Swap:          8.0Gi          0B       8.0Gi"
    log_success "✓ Host has 82GB available RAM"
    simulate_output ""

    simulate_command "df -h /var/lib/cloud-hypervisor" ""
    simulate_output "Filesystem      Size  Used Avail Use% Mounted on"
    simulate_output "/dev/nvme0n1p1  2.0T  156G  1.8T   9% /"
    log_success "✓ Host has 1.8TB available disk space"
    simulate_output ""

    log_info "Summary of Cloud Hypervisor VMs..."
    simulate_command "ps aux | grep cloud-hypervisor | grep -v grep" ""
    simulate_output "root     13201  2.1  0.8 8388608 1048576 ?     Sl   10:45   1:23 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4140.sock ..."
    simulate_output "root     13307  2.3  0.9 8388608 1179648 ?     Sl   10:47   1:34 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4141.sock ..."
    simulate_output "root     13308  2.2  0.9 8388608 1146880 ?     Sl   10:47   1:32 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4142.sock ..."
    simulate_output "root     13309  2.4  0.9 8388608 1179648 ?     Sl   10:47   1:35 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4143.sock ..."
    simulate_output "root     13310  2.3  0.9 8388608 1163264 ?     Sl   10:47   1:33 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4144.sock ..."
    simulate_output "root     13311  3.8  2.7 8388608 3538944 ?     Sl   10:47   2:15 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4145.sock ..."
    simulate_output "root     13312  3.9  2.8 8388608 3604480 ?     Sl   10:47   2:17 cloud-hypervisor --api-socket /run/cloud-hypervisor/vm-4146.sock ..."
    log_success "✓ All 7 VMs running"
    log_success "✓ Total VM memory usage: ~10GB (VMs) + overhead"
    simulate_output ""

    sleep 2
}

###############################################################################
# Phase 6: Final Summary
###############################################################################

phase6_summary() {
    log_step "DEPLOYMENT COMPLETE!"

    cat <<EOF

╔══════════════════════════════════════════════════════════════════════╗
║                     DEPLOYMENT SUCCESS SUMMARY                      ║
╚══════════════════════════════════════════════════════════════════════╝

${GREEN}✓ Infrastructure Deployed Successfully${NC}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}VIRTUAL MACHINES (7 total)${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  VM ID   Hostname              IP               Cores   RAM     Role
  ─────   ──────────────────    ──────────────   ─────   ─────   ────────────
  4140    os0.cluster.local     10.1.199.140     4       8GB     Jump Host
  4141    os1.cluster.local     10.1.199.141     4       8GB     K8s Master
  4142    os2.cluster.local     10.1.199.142     4       8GB     K8s Worker
  4143    os3.cluster.local     10.1.199.143     4       8GB     K8s Worker
  4144    os4.cluster.local     10.1.199.144     4       8GB     K8s Worker
  4145    os5.cluster.local     10.1.199.145     4       32GB    OpenStack
  4146    os6.cluster.local     10.1.199.146     4       32GB    OpenStack

  ${GREEN}✓${NC} All VMs created with Cloud Hypervisor
  ${GREEN}✓${NC} Dual network interfaces (chbr1199 + chbr2199)
  ${GREEN}✓${NC} 3 disks per VM: 1x50GB system + 2x100GB OSD

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}KUBERNETES CLUSTER${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Version:         v1.31.0
  Nodes:           4 (os1, os2, os3, os4)
  Control Plane:   os1
  Status:          ${GREEN}All nodes Ready${NC}
  CNI:             Calico
  Runtime:         containerd 1.7.22

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}ROOK-CEPH STORAGE${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Status:          ${GREEN}HEALTH_OK${NC}
  Monitors:        3 (a, b, c)
  OSDs:            8 (2 per node × 4 nodes)
  Total Storage:   800GB
  Used:            8.1GB
  Available:       792GB
  Storage Class:   rook-ceph-block (RBD)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}NETWORK CONFIGURATION${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Internal Bridge: chbr1199 (10.1.199.0/24)
    └─ Gateway:    10.1.199.254
    └─ TAP devices: tap-4140-0 through tap-4146-0

  External Bridge: chbr2199 (10.2.199.0/24)
    └─ Gateway:    10.2.199.254
    └─ TAP devices: tap-4140-1 through tap-4146-1

  ${GREEN}✓${NC} IP forwarding enabled
  ${GREEN}✓${NC} NAT configured for external bridge
  ${GREEN}✓${NC} 14 TAP devices active (2 per VM)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}HOST RESOURCES${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total RAM:       128GB
  Used by VMs:     ~10GB (7 VMs)
  Available:       82GB
  Disk Space:      1.8TB available

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}ACCESS INFORMATION${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Jump Host:       ssh ubuntu@10.1.199.140
  Kubernetes:      kubectl --kubeconfig /home/ubuntu/.kube/config
  Ceph Dashboard:  kubectl -n rook-ceph get svc rook-ceph-mgr-dashboard

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}NEXT STEPS${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. Deploy OpenStack:
     ${YELLOW}./deploy_openstack.sh${NC}

  2. Access Kubernetes:
     ${YELLOW}ssh ubuntu@10.1.199.140${NC}
     ${YELLOW}kubectl get nodes${NC}

  3. Check Ceph status:
     ${YELLOW}kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s${NC}

  4. Create test volume:
     ${YELLOW}kubectl apply -f examples/mysql-pvc.yaml${NC}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CYAN}PERFORMANCE METRICS${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total deployment time:     ~25 minutes
  VM creation:               ~2 minutes
  Kubernetes deployment:     ~18 minutes
  Rook-Ceph deployment:      ~5 minutes

  Average VM boot time:      ~22 seconds
  VM memory overhead:        ~110MB per VM
  Cloud Hypervisor CPU:      ~2-4% per VM (idle)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${GREEN}╔═══════════════════════════════════════════════════════════════╗
║  CLOUD HYPERVISOR DEPLOYMENT SUCCESSFUL!                      ║
║                                                               ║
║  Your OpenStack-Ceph infrastructure is ready for production. ║
╚═══════════════════════════════════════════════════════════════╝${NC}

EOF

    sleep 2
}

###############################################################################
# Main Execution
###############################################################################

main() {
    clear

    cat <<EOF
${BLUE}
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║         CLOUD HYPERVISOR DEPLOYMENT SIMULATION                       ║
║                                                                       ║
║    OpenStack-Ceph Infrastructure on Bare Metal Linux Server          ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
${NC}

This simulation demonstrates a complete deployment of the OpenStack-Ceph
virtualized infrastructure using Cloud Hypervisor on a bare metal server.

Phases:
  1. Host Setup (Cloud Hypervisor installation)
  2. Single VM Test (verification)
  3. Full Deployment (7 VMs)
  4. Rook-Ceph Deployment
  5. Verification
  6. Summary

Press Enter to start...
EOF

    read -r

    show_system_info
    phase1_host_setup
    phase2_single_vm_test
    phase3_full_deployment
    phase4_rook_ceph_deployment
    phase5_verification
    phase6_summary

    echo ""
    log_success "Simulation complete!"
    echo ""
}

# Run simulation
main
