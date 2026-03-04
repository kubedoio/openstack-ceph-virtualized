#!/usr/bin/env bash
###############################################################################
# create-vm.sh - Create and configure a VM using hypervisor abstraction
#
# Usage: create-vm.sh template_id vm_id dns_name ip_address gw_address
#
# This script works with both Proxmox VE and Cloud Hypervisor through
# the hypervisor abstraction layer.
###############################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load hypervisor abstraction layer
source "$SCRIPT_DIR/lib/hypervisor.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/rook_ceph.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

###############################################################################
# Usage and argument parsing
###############################################################################

if [[ $# -lt 5 ]]; then
    echo "Usage: $0 template_id vm_id dns_name ip_address gw_address" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 4444 4141 os1.cluster.local 10.1.199.141/24 10.1.199.254" >&2
    echo "" >&2
    echo "Environment:" >&2
    echo "  HYPERVISOR=auto|proxmox|cloudhypervisor (default: auto)" >&2
    exit 1
fi

TEMPLATE_ID="$1"
VM_ID="$2"
VM_NAME="$3"
VM_IP_CIDR="$4"
VM_GATEWAY="$5"

# VM configuration
VM_CORES=4
VM_MEMORY_MB=8192
VM_DISK_SIZE_INCREASE_GB=25
VM_OSD_DISK_SIZE_GB=100

# SSH keys file
PUB_KEYS_FILE="${PUB_KEY_FILE:-pub_keys}"

###############################################################################
# Initialize hypervisor
###############################################################################

echo "==================================="
echo "Creating VM with Hypervisor Abstraction"
echo "==================================="
echo "VM ID:        $VM_ID"
echo "VM Name:      $VM_NAME"
echo "IP/CIDR:      $VM_IP_CIDR"
echo "Gateway:      $VM_GATEWAY"
echo "Template ID:  $TEMPLATE_ID"
echo "==================================="

# Initialize hypervisor detection
hv_init || {
    echo "ERROR: Failed to initialize hypervisor" >&2
    exit 1
}

echo "INFO: Using hypervisor: $(hv_get_type)" >&2
echo ""

###############################################################################
# Check if VM already exists
###############################################################################

if hv_vm_exists "$VM_ID"; then
    echo "ERROR: VM $VM_ID already exists" >&2
    exit 1
fi

###############################################################################
# Create VM from template
###############################################################################

echo "Step 1: Cloning template $TEMPLATE_ID to VM $VM_ID..."

hv_clone_template "$VM_ID" "$TEMPLATE_ID" || {
    echo "ERROR: Failed to clone template" >&2
    exit 1
}

###############################################################################
# Configure VM resources
###############################################################################

echo "Step 2: Configuring VM resources..."

# Set CPU cores
hv_set_cores "$VM_ID" "$VM_CORES" || {
    echo "ERROR: Failed to set CPU cores" >&2
    exit 1
}

# Set memory
hv_set_memory "$VM_ID" "$VM_MEMORY_MB" || {
    echo "ERROR: Failed to set memory" >&2
    exit 1
}

###############################################################################
# Configure cloud-init
###############################################################################

echo "Step 3: Configuring cloud-init..."

if hv_is_proxmox; then
    # Proxmox built-in cloud-init
    hv_set_cloudinit_user "$VM_ID" "ubuntu" "$PUB_KEYS_FILE" || {
        echo "ERROR: Failed to configure cloud-init user" >&2
        exit 1
    }

    hv_set_cloudinit_network "$VM_ID" "$VM_IP_CIDR" "$VM_GATEWAY" || {
        echo "ERROR: Failed to configure cloud-init network" >&2
        exit 1
    }

elif hv_is_cloudhypervisor; then
    # Cloud Hypervisor: generate NoCloud ISO
    source "$SCRIPT_DIR/lib/common/cloudinit.sh"

    VM_DIR="$CH_VM_DIR/vm-${VM_ID}"
    CLOUDINIT_ISO="${VM_DIR}/cloudinit.iso"

    # Extract hostname from FQDN
    VM_HOSTNAME="${VM_NAME%%.*}"

    # Generate cloud-init ISO
    generate_cloudinit_iso \
        "$CLOUDINIT_ISO" \
        "vm-${VM_ID}" \
        "$VM_HOSTNAME" \
        "$VM_NAME" \
        "$VM_IP_CIDR" \
        "$VM_GATEWAY" \
        "$PUB_KEYS_FILE" \
        "8.8.8.8,8.8.4.4" || {
        echo "ERROR: Failed to generate cloud-init ISO" >&2
        exit 1
    }

    # Attach cloud-init ISO
    hv_set_cloudinit "$VM_ID" "$CLOUDINIT_ISO" || {
        echo "ERROR: Failed to attach cloud-init ISO" >&2
        exit 1
    }
fi

###############################################################################
# Resize system disk
###############################################################################

echo "Step 4: Resizing system disk..."

hv_resize_disk "$VM_ID" 0 "$VM_DISK_SIZE_INCREASE_GB" || {
    echo "ERROR: Failed to resize system disk" >&2
    exit 1
}

###############################################################################
# Add OSD disks for Ceph
###############################################################################

echo "Step 5: Adding OSD disks for Ceph..."

if hv_is_proxmox; then
    # Proxmox: use storage:size format
    hv_add_disk "$VM_ID" "local" "$VM_OSD_DISK_SIZE_GB" 1 || {
        echo "ERROR: Failed to add first OSD disk" >&2
        exit 1
    }

    hv_add_disk "$VM_ID" "local" "$VM_OSD_DISK_SIZE_GB" 2 || {
        echo "ERROR: Failed to add second OSD disk" >&2
        exit 1
    }

elif hv_is_cloudhypervisor; then
    # Cloud Hypervisor: create raw disk images
    hv_add_disk "$VM_ID" "$VM_OSD_DISK_SIZE_GB" 1 || {
        echo "ERROR: Failed to add first OSD disk" >&2
        exit 1
    }

    hv_add_disk "$VM_ID" "$VM_OSD_DISK_SIZE_GB" 2 || {
        echo "ERROR: Failed to add second OSD disk" >&2
        exit 1
    }
fi

###############################################################################
# Configure networking (Cloud Hypervisor only)
###############################################################################

if hv_is_cloudhypervisor; then
    echo "Step 6: Configuring network interfaces..."

    # Internal network (eth0) - management
    INTERNAL_BRIDGE="${INTERNAL_BRIDGE:-chbr1199}"
    hv_add_network "$VM_ID" "$INTERNAL_BRIDGE" || {
        echo "ERROR: Failed to add internal network interface" >&2
        exit 1
    }

    # External network (ens19) - provider
    EXTERNAL_BRIDGE="${EXTERNAL_BRIDGE:-chbr2199}"
    hv_add_network "$VM_ID" "$EXTERNAL_BRIDGE" || {
        echo "ERROR: Failed to add external network interface" >&2
        exit 1
    }
fi

###############################################################################
# Summary
###############################################################################

echo ""
echo "==================================="
echo "VM Created Successfully!"
echo "==================================="
echo "VM ID:        $VM_ID"
echo "VM Name:      $VM_NAME"
echo "IP Address:   $VM_IP_CIDR"
echo "Cores:        $VM_CORES"
echo "Memory:       ${VM_MEMORY_MB}MB"
echo "OSD Disks:    2 x ${VM_OSD_DISK_SIZE_GB}GB"
echo "Hypervisor:   $(hv_get_type)"
echo ""
echo "To start the VM, run:"
echo "  hv_start_vm $VM_ID"
echo ""
echo "Note: The VM is NOT started automatically."
echo "==================================="

exit 0
