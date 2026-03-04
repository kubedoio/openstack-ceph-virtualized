#!/usr/bin/env bash
###############################################################################
# setup-cloud-hypervisor.sh - Setup Cloud Hypervisor host environment
#
# This script prepares a bare metal Linux server for Cloud Hypervisor VMs.
# It installs required packages, creates network bridges, and configures
# the system for VM deployment.
#
# Run with sudo or as root.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/rook_ceph.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Load utilities
source "$SCRIPT_DIR/lib/common/network.sh"

###############################################################################
# Configuration
###############################################################################

INTERNAL_BRIDGE="${INTERNAL_BRIDGE:-chbr1199}"
INTERNAL_IP="${INTERNAL_IP:-10.1.199.254/24}"
EXTERNAL_BRIDGE="${EXTERNAL_BRIDGE:-chbr2199}"
EXTERNAL_IP="${EXTERNAL_IP:-10.2.199.254/24}"

CH_VM_DIR="${CH_VM_DIR:-/var/lib/cloud-hypervisor/vms}"
CH_IMAGE_DIR="${CH_IMAGE_DIR:-/var/lib/cloud-hypervisor/images}"
CH_API_SOCKET="${CH_API_SOCKET:-/run/cloud-hypervisor}"

###############################################################################
# Check root privileges
###############################################################################

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root or with sudo" >&2
    exit 1
fi

###############################################################################
# Detect OS
###############################################################################

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
else
    echo "ERROR: Cannot detect OS" >&2
    exit 1
fi

echo "==================================="
echo "Cloud Hypervisor Host Setup"
echo "==================================="
echo "Operating System: $OS_ID $OS_VERSION"
echo "Internal Bridge:  $INTERNAL_BRIDGE ($INTERNAL_IP)"
echo "External Bridge:  $EXTERNAL_BRIDGE ($EXTERNAL_IP)"
echo "==================================="
echo ""

###############################################################################
# Install required packages
###############################################################################

echo "Step 1: Installing required packages..."

case "$OS_ID" in
    ubuntu|debian)
        apt-get update
        apt-get install -y \
            qemu-utils \
            genisoimage \
            bridge-utils \
            iproute2 \
            iptables \
            curl \
            wget \
            jq \
            socat
        ;;
    centos|rhel|fedora)
        yum install -y \
            qemu-img \
            genisoimage \
            bridge-utils \
            iproute \
            iptables \
            curl \
            wget \
            jq \
            socat
        ;;
    *)
        echo "WARNING: Unknown OS: $OS_ID"
        echo "WARNING: Please install manually: qemu-utils, genisoimage, bridge-utils, iproute2, iptables, jq"
        ;;
esac

echo "INFO: Packages installed successfully"
echo ""

###############################################################################
# Install Cloud Hypervisor
###############################################################################

echo "Step 2: Installing Cloud Hypervisor..."

if command -v cloud-hypervisor >/dev/null 2>&1; then
    CH_VERSION=$(cloud-hypervisor --version | head -n1)
    echo "INFO: Cloud Hypervisor already installed: $CH_VERSION"
else
    echo "INFO: Downloading Cloud Hypervisor..."

    # Download latest release
    CH_VERSION="v42.0"  # Update this to latest stable version
    CH_URL="https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/${CH_VERSION}/cloud-hypervisor-static"
    CH_REMOTE_URL="https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/${CH_VERSION}/ch-remote-static"

    curl -L -o /tmp/cloud-hypervisor "$CH_URL" || {
        echo "ERROR: Failed to download cloud-hypervisor" >&2
        exit 1
    }

    curl -L -o /tmp/ch-remote "$CH_REMOTE_URL" || {
        echo "ERROR: Failed to download ch-remote" >&2
        exit 1
    }

    # Install binaries
    install -m 755 /tmp/cloud-hypervisor /usr/local/bin/cloud-hypervisor
    install -m 755 /tmp/ch-remote /usr/local/bin/ch-remote

    rm -f /tmp/cloud-hypervisor /tmp/ch-remote

    echo "INFO: Cloud Hypervisor installed: $(cloud-hypervisor --version | head -n1)"
fi

echo ""

###############################################################################
# Create directories
###############################################################################

echo "Step 3: Creating directories..."

mkdir -p "$CH_VM_DIR"
mkdir -p "$CH_IMAGE_DIR"
mkdir -p "$CH_API_SOCKET"

echo "INFO: Directories created:"
echo "  - VMs:    $CH_VM_DIR"
echo "  - Images: $CH_IMAGE_DIR"
echo "  - Sockets: $CH_API_SOCKET"
echo ""

###############################################################################
# Setup network bridges
###############################################################################

echo "Step 4: Setting up network bridges..."

# Create internal bridge
create_bridge "$INTERNAL_BRIDGE" "$INTERNAL_IP" || {
    echo "ERROR: Failed to create internal bridge" >&2
    exit 1
}

# Create external bridge
create_bridge "$EXTERNAL_BRIDGE" "$EXTERNAL_IP" || {
    echo "ERROR: Failed to create external bridge" >&2
    exit 1
}

# Enable IP forwarding
enable_ip_forwarding || {
    echo "ERROR: Failed to enable IP forwarding" >&2
    exit 1
}

# Setup NAT for external bridge
setup_nat "$EXTERNAL_BRIDGE" || {
    echo "WARNING: Failed to setup NAT (VMs may not have internet access)"
}

echo "INFO: Network bridges configured successfully"
echo ""

###############################################################################
# Make bridge setup persistent
###############################################################################

echo "Step 5: Making bridge configuration persistent..."

# Create systemd service for bridge setup
cat > /etc/systemd/system/cloudhypervisor-bridges.service <<EOF
[Unit]
Description=Cloud Hypervisor Network Bridges
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'source $SCRIPT_DIR/lib/common/network.sh && setup_cloudhypervisor_network $INTERNAL_BRIDGE $INTERNAL_IP $EXTERNAL_BRIDGE $EXTERNAL_IP'
ExecStop=/bin/bash -c 'source $SCRIPT_DIR/lib/common/network.sh && cleanup_cloudhypervisor_network $INTERNAL_BRIDGE $EXTERNAL_BRIDGE'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudhypervisor-bridges.service

echo "INFO: Bridge configuration will persist across reboots"
echo ""

###############################################################################
# Configure firewall (if active)
###############################################################################

echo "Step 6: Configuring firewall..."

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "INFO: UFW firewall detected, adding rules..."

    ufw allow in on "$INTERNAL_BRIDGE"
    ufw allow in on "$EXTERNAL_BRIDGE"

    echo "INFO: UFW rules added"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    echo "INFO: firewalld detected, adding rules..."

    firewall-cmd --permanent --zone=trusted --add-interface="$INTERNAL_BRIDGE"
    firewall-cmd --permanent --zone=trusted --add-interface="$EXTERNAL_BRIDGE"
    firewall-cmd --reload

    echo "INFO: firewalld rules added"
else
    echo "INFO: No active firewall detected, skipping firewall configuration"
fi

echo ""

###############################################################################
# Download Ubuntu cloud image template
###############################################################################

echo "Step 7: Downloading Ubuntu cloud image template..."

source "$SCRIPT_DIR/lib/common/storage.sh"

TEMPLATE_IMAGE="$CH_IMAGE_DIR/ubuntu-24.04-cloudimg.qcow2"
TEMPLATE_RAW="$CH_IMAGE_DIR/template-${TEMPLATE_ID:-4444}.raw"

if [[ -f "$TEMPLATE_RAW" ]]; then
    echo "INFO: Template already exists: $TEMPLATE_RAW"
else
    # Download Ubuntu 24.04 cloud image
    download_ubuntu_cloud_image "$TEMPLATE_IMAGE" noble || {
        echo "ERROR: Failed to download Ubuntu cloud image" >&2
        exit 1
    }

    # Convert to raw format
    convert_qcow2_to_raw "$TEMPLATE_IMAGE" "$TEMPLATE_RAW" || {
        echo "ERROR: Failed to convert template to raw format" >&2
        exit 1
    }

    echo "INFO: Template created: $TEMPLATE_RAW"
fi

echo ""

###############################################################################
# Verification
###############################################################################

echo "Step 8: Verifying installation..."

ERRORS=0

# Check Cloud Hypervisor
if ! command -v cloud-hypervisor >/dev/null 2>&1; then
    echo "ERROR: cloud-hypervisor not found in PATH" >&2
    ERRORS=$((ERRORS + 1))
fi

if ! command -v ch-remote >/dev/null 2>&1; then
    echo "ERROR: ch-remote not found in PATH" >&2
    ERRORS=$((ERRORS + 1))
fi

# Check bridges
if ! bridge_exists "$INTERNAL_BRIDGE"; then
    echo "ERROR: Internal bridge $INTERNAL_BRIDGE not found" >&2
    ERRORS=$((ERRORS + 1))
fi

if ! bridge_exists "$EXTERNAL_BRIDGE"; then
    echo "ERROR: External bridge $EXTERNAL_BRIDGE not found" >&2
    ERRORS=$((ERRORS + 1))
fi

# Check IP forwarding
if [[ $(cat /proc/sys/net/ipv4/ip_forward) != "1" ]]; then
    echo "ERROR: IP forwarding not enabled" >&2
    ERRORS=$((ERRORS + 1))
fi

# Check directories
if [[ ! -d "$CH_VM_DIR" ]]; then
    echo "ERROR: VM directory not found: $CH_VM_DIR" >&2
    ERRORS=$((ERRORS + 1))
fi

if [[ ! -d "$CH_IMAGE_DIR" ]]; then
    echo "ERROR: Image directory not found: $CH_IMAGE_DIR" >&2
    ERRORS=$((ERRORS + 1))
fi

# Check template
if [[ ! -f "$TEMPLATE_RAW" ]]; then
    echo "WARNING: Template image not found: $TEMPLATE_RAW"
    echo "WARNING: Run: source lib/common/storage.sh && download_ubuntu_cloud_image ..."
fi

echo ""

if [[ $ERRORS -eq 0 ]]; then
    echo "==================================="
    echo "✓ Setup completed successfully!"
    echo "==================================="
    echo ""
    echo "Cloud Hypervisor host is ready for VM deployment."
    echo ""
    echo "Next steps:"
    echo "  1. Review configuration in: $CONFIG_FILE"
    echo "  2. Deploy Rook-Ceph cluster: ./deploy_rook_ceph.sh"
    echo ""
    echo "Network bridges:"
    echo "  - Internal: $INTERNAL_BRIDGE ($INTERNAL_IP)"
    echo "  - External: $EXTERNAL_BRIDGE ($EXTERNAL_IP)"
    echo ""
    echo "Template: $TEMPLATE_RAW"
    echo "==================================="
    exit 0
else
    echo "==================================="
    echo "✗ Setup completed with $ERRORS error(s)"
    echo "==================================="
    echo "Please fix the errors above and try again."
    exit 1
fi
