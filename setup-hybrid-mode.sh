#!/usr/bin/env bash
###############################################################################
# setup-hybrid-mode.sh - Setup Proxmox host for hybrid mode
#
# This script prepares a Proxmox VE host to run Cloud Hypervisor VMs
# alongside native Proxmox VMs, using Proxmox bridges.
#
# Prerequisites:
#   - Running Proxmox VE installation
#   - Root/sudo access
#   - Internet connection for downloads
#
# What it does:
#   1. Verifies Proxmox VE installation
#   2. Installs Cloud Hypervisor
#   3. Verifies Proxmox bridges (vmbr1199, vmbr2199)
#   4. Downloads and converts Ubuntu cloud image template
#   5. Sets up required directories
#
# Usage:
#   sudo ./setup-hybrid-mode.sh
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/rook_ceph.conf" ]]; then
    source "$SCRIPT_DIR/rook_ceph.conf"
fi

# Hybrid mode defaults
HYBRID_BRIDGE_INTERNAL="${HYBRID_BRIDGE_INTERNAL:-vmbr1199}"
HYBRID_BRIDGE_EXTERNAL="${HYBRID_BRIDGE_EXTERNAL:-vmbr2199}"
CH_VM_DIR="${CH_VM_DIR:-/var/lib/cloud-hypervisor/vms}"
CH_IMAGE_DIR="${CH_IMAGE_DIR:-/var/lib/cloud-hypervisor/images}"
CH_API_SOCKET="${CH_API_SOCKET:-/run/cloud-hypervisor}"

# Cloud Hypervisor version
CH_VERSION="${CH_VERSION:-v39.0}"
CH_DOWNLOAD_URL="https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/${CH_VERSION}/cloud-hypervisor-static"

# Ubuntu cloud image
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
TEMPLATE_IMAGE_NAME="ubuntu-${UBUNTU_VERSION}-cloudimg-template.raw"

###############################################################################
# Verification Functions
###############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_proxmox() {
    info "Checking Proxmox VE installation..."

    if ! command -v qm >/dev/null 2>&1; then
        error "Proxmox VE not found (qm command missing)"
        error "This script requires a Proxmox VE installation"
        exit 1
    fi

    if ! qm list >/dev/null 2>&1; then
        error "Cannot execute qm commands"
        error "Are you running as root/sudo?"
        exit 1
    fi

    local pve_version
    pve_version=$(pveversion 2>/dev/null || echo "unknown")
    info "Proxmox VE detected: $pve_version"

    # Verify qemu-img is available (critical for template conversion)
    if ! command -v qemu-img >/dev/null 2>&1; then
        error "qemu-img not found"
        error "This is required for image conversion (qcow2 to raw)"
        error ""
        error "On Proxmox, qemu-img should be provided by pve-qemu-kvm package"
        error "Try fixing with: apt install --reinstall pve-qemu-kvm"
        exit 1
    fi

    info "qemu-img available: $(qemu-img --version | head -n1)"
}

check_bridges() {
    info "Checking Proxmox bridges..."

    local missing_bridges=()

    if ! ip link show "$HYBRID_BRIDGE_INTERNAL" >/dev/null 2>&1; then
        missing_bridges+=("$HYBRID_BRIDGE_INTERNAL")
    else
        info "Bridge $HYBRID_BRIDGE_INTERNAL exists ✓"
    fi

    if ! ip link show "$HYBRID_BRIDGE_EXTERNAL" >/dev/null 2>&1; then
        missing_bridges+=("$HYBRID_BRIDGE_EXTERNAL")
    else
        info "Bridge $HYBRID_BRIDGE_EXTERNAL exists ✓"
    fi

    if [[ ${#missing_bridges[@]} -gt 0 ]]; then
        error "Missing required Proxmox bridges: ${missing_bridges[*]}"
        echo ""
        echo "Create bridges in Proxmox Web UI:"
        echo "  1. Navigate to: Datacenter → [Your Node] → System → Network"
        echo "  2. Create Linux Bridge with name: ${missing_bridges[0]}"
        echo "  3. Configure IP address and subnet (e.g., 10.1.199.254/24)"
        echo "  4. Repeat for additional bridges"
        echo ""
        echo "Or create via CLI:"
        for bridge in "${missing_bridges[@]}"; do
            echo "  pvesh create /nodes/\$(hostname)/network --iface $bridge --type bridge --autostart 1"
        done
        echo "  pvesh set /nodes/\$(hostname)/network"
        echo ""
        exit 1
    fi

    info "All required bridges present ✓"
}

###############################################################################
# Installation Functions
###############################################################################

install_cloud_hypervisor() {
    info "Installing Cloud Hypervisor..."

    if command -v cloud-hypervisor >/dev/null 2>&1; then
        local current_version
        current_version=$(cloud-hypervisor --version 2>/dev/null | head -n1 || echo "unknown")
        info "Cloud Hypervisor already installed: $current_version"

        read -p "Reinstall/upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    info "Downloading Cloud Hypervisor ${CH_VERSION}..."

    local tmp_file="/tmp/cloud-hypervisor-$$.tmp"
    if ! curl -sSL -o "$tmp_file" "$CH_DOWNLOAD_URL"; then
        error "Failed to download Cloud Hypervisor"
        rm -f "$tmp_file"
        exit 1
    fi

    info "Installing to /usr/local/bin/cloud-hypervisor..."
    chmod +x "$tmp_file"
    mv "$tmp_file" /usr/local/bin/cloud-hypervisor

    # Verify installation
    if cloud-hypervisor --version >/dev/null 2>&1; then
        local installed_version
        installed_version=$(cloud-hypervisor --version | head -n1)
        info "Cloud Hypervisor installed successfully: $installed_version ✓"
    else
        error "Cloud Hypervisor installation verification failed"
        exit 1
    fi
}

install_dependencies() {
    info "Installing dependencies..."

    # Check for qemu-img from Proxmox packages first
    local qemu_img_available=false
    if command -v qemu-img >/dev/null 2>&1; then
        qemu_img_available=true
        info "qemu-img available from Proxmox packages ✓"
    fi

    # Packages that are safe to install on Proxmox
    local packages=(
        genisoimage          # For cloud-init ISO generation
        curl                 # For downloads
        bridge-utils         # For bridge management
    )

    # Only add qemu-utils if qemu-img is not available and we're NOT on Proxmox
    if [[ "$qemu_img_available" == "false" ]]; then
        # Check if this is a Proxmox system
        if command -v pveversion >/dev/null 2>&1; then
            error "qemu-img not found but this is a Proxmox system"
            error "Proxmox should provide qemu-img via pve-qemu-kvm package"
            error "Try: apt install --reinstall pve-qemu-kvm"
            exit 1
        else
            # Not Proxmox, safe to install qemu-utils
            packages+=(qemu-utils)
        fi
    fi

    local missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        info "All dependencies already installed ✓"
        return 0
    fi

    info "Installing missing packages: ${missing_packages[*]}"
    apt-get update -qq

    # Install packages, but avoid removing proxmox-ve
    if ! apt-get install -y "${missing_packages[@]}" 2>&1 | tee /tmp/apt-install.log; then
        if grep -q "proxmox-ve" /tmp/apt-install.log; then
            error "Package installation would remove proxmox-ve"
            error "This is likely due to qemu-utils conflicting with Proxmox packages"
            error "Proxmox provides qemu-img via its own packages"
            rm -f /tmp/apt-install.log
            exit 1
        fi
        rm -f /tmp/apt-install.log
        exit 1
    fi
    rm -f /tmp/apt-install.log

    info "Dependencies installed ✓"
}

###############################################################################
# Setup Functions
###############################################################################

setup_directories() {
    info "Creating Cloud Hypervisor directories..."

    mkdir -p "$CH_VM_DIR" "$CH_IMAGE_DIR" "$CH_API_SOCKET"

    info "Directories created:"
    info "  VM storage: $CH_VM_DIR"
    info "  Image storage: $CH_IMAGE_DIR"
    info "  API sockets: $CH_API_SOCKET"
}

download_ubuntu_template() {
    info "Setting up Ubuntu cloud image template..."

    local template_path="$CH_IMAGE_DIR/$TEMPLATE_IMAGE_NAME"

    if [[ -f "$template_path" ]]; then
        info "Template already exists: $template_path"

        read -p "Re-download? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    local tmp_qcow="/tmp/ubuntu-cloudimg-$$.qcow2"

    info "Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
    if ! curl -sSL -o "$tmp_qcow" "$UBUNTU_IMAGE_URL"; then
        error "Failed to download Ubuntu cloud image"
        rm -f "$tmp_qcow"
        exit 1
    fi

    info "Converting qcow2 to raw format..."
    if ! qemu-img convert -f qcow2 -O raw "$tmp_qcow" "$template_path"; then
        error "Failed to convert image"
        rm -f "$tmp_qcow"
        exit 1
    fi

    rm -f "$tmp_qcow"

    info "Resizing template to 50GB..."
    if ! qemu-img resize "$template_path" 50G; then
        warn "Failed to resize template (non-fatal)"
    fi

    local size
    size=$(du -h "$template_path" | cut -f1)
    info "Template created: $template_path ($size) ✓"
}

setup_systemd_service() {
    info "Setting up systemd service for Cloud Hypervisor VMs..."

    local service_file="/etc/systemd/system/cloud-hypervisor-vms.service"

    cat > "$service_file" <<'EOF'
[Unit]
Description=Cloud Hypervisor VM Management
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/bin/cloud-hypervisor-cleanup.sh

[Install]
WantedBy=multi-user.target
EOF

    # Create cleanup script
    cat > /usr/local/bin/cloud-hypervisor-cleanup.sh <<'EOF'
#!/bin/bash
# Gracefully shutdown all Cloud Hypervisor VMs on host shutdown
PID_FILE="/var/run/cloud-hypervisor-vms.pids"
if [[ -f "$PID_FILE" ]]; then
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping Cloud Hypervisor VM (PID: $pid)..."
            kill -TERM "$pid"
        fi
    done < "$PID_FILE"
    sleep 2
fi
EOF
    chmod +x /usr/local/bin/cloud-hypervisor-cleanup.sh

    systemctl daemon-reload
    systemctl enable cloud-hypervisor-vms.service

    info "Systemd service configured ✓"
}

###############################################################################
# Configuration
###############################################################################

configure_rook_ceph_conf() {
    info "Updating rook_ceph.conf for hybrid mode..."

    local conf_file="$SCRIPT_DIR/rook_ceph.conf"

    if ! grep -q "^HYPERVISOR=" "$conf_file" 2>/dev/null; then
        warn "rook_ceph.conf not found or missing HYPERVISOR setting"
        warn "You may need to manually set HYPERVISOR=proxmox-cloudhypervisor"
        return 0
    fi

    # Check current setting
    local current_hv
    current_hv=$(grep "^HYPERVISOR=" "$conf_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [[ "$current_hv" == "proxmox-cloudhypervisor" ]]; then
        info "HYPERVISOR already set to proxmox-cloudhypervisor ✓"
        return 0
    fi

    info "Current HYPERVISOR setting: $current_hv"
    read -p "Update to 'proxmox-cloudhypervisor'? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sed -i.bak 's/^HYPERVISOR=.*/HYPERVISOR="proxmox-cloudhypervisor"/' "$conf_file"
        info "Updated HYPERVISOR=proxmox-cloudhypervisor ✓"
        info "Backup saved: $conf_file.bak"
    fi
}

###############################################################################
# Verification
###############################################################################

verify_setup() {
    info "Verifying hybrid mode setup..."

    local errors=0

    # Check Cloud Hypervisor
    if ! command -v cloud-hypervisor >/dev/null 2>&1; then
        error "Cloud Hypervisor not found"
        ((errors++))
    else
        info "✓ Cloud Hypervisor installed"
    fi

    # Check Proxmox
    if ! command -v qm >/dev/null 2>&1; then
        error "Proxmox VE not found"
        ((errors++))
    else
        info "✓ Proxmox VE installed"
    fi

    # Check bridges
    if ! ip link show "$HYBRID_BRIDGE_INTERNAL" >/dev/null 2>&1; then
        error "Bridge $HYBRID_BRIDGE_INTERNAL not found"
        ((errors++))
    else
        info "✓ Bridge $HYBRID_BRIDGE_INTERNAL exists"
    fi

    if ! ip link show "$HYBRID_BRIDGE_EXTERNAL" >/dev/null 2>&1; then
        error "Bridge $HYBRID_BRIDGE_EXTERNAL not found"
        ((errors++))
    else
        info "✓ Bridge $HYBRID_BRIDGE_EXTERNAL exists"
    fi

    # Check directories
    if [[ ! -d "$CH_VM_DIR" ]]; then
        error "VM directory not found: $CH_VM_DIR"
        ((errors++))
    else
        info "✓ VM directory: $CH_VM_DIR"
    fi

    # Check template
    if [[ ! -f "$CH_IMAGE_DIR/$TEMPLATE_IMAGE_NAME" ]]; then
        warn "Template not found: $CH_IMAGE_DIR/$TEMPLATE_IMAGE_NAME"
        warn "You may need to download it manually"
    else
        info "✓ Template image: $CH_IMAGE_DIR/$TEMPLATE_IMAGE_NAME"
    fi

    if [[ $errors -gt 0 ]]; then
        error "Verification failed with $errors error(s)"
        return 1
    fi

    info "All checks passed ✓"
    return 0
}

###############################################################################
# Main
###############################################################################

main() {
    echo "=============================================================================="
    echo "  Hybrid Mode Setup - Cloud Hypervisor on Proxmox VE"
    echo "=============================================================================="
    echo ""

    check_root
    check_proxmox
    check_bridges

    echo ""
    info "Starting installation..."
    echo ""

    install_dependencies
    install_cloud_hypervisor
    setup_directories
    download_ubuntu_template
    setup_systemd_service
    configure_rook_ceph_conf

    echo ""
    info "Setup complete!"
    echo ""

    verify_setup

    echo ""
    echo "=============================================================================="
    echo "  Next Steps"
    echo "=============================================================================="
    echo ""
    echo "1. Verify configuration in rook_ceph.conf:"
    echo "   HYPERVISOR=proxmox-cloudhypervisor"
    echo "   HYBRID_BRIDGE_INTERNAL=$HYBRID_BRIDGE_INTERNAL"
    echo "   HYBRID_BRIDGE_EXTERNAL=$HYBRID_BRIDGE_EXTERNAL"
    echo ""
    echo "2. Create VMs using the existing scripts:"
    echo "   ./create-vm.sh 4444 5001 os1.local 10.1.199.141/24 10.1.199.254"
    echo ""
    echo "3. Deploy Rook-Ceph cluster:"
    echo "   ./deploy_rook_ceph.sh"
    echo ""
    echo "Note: Cloud Hypervisor VMs will coexist with Proxmox VMs"
    echo "      VM IDs 5000+ are reserved for Cloud Hypervisor VMs"
    echo ""
    echo "=============================================================================="
}

main "$@"
