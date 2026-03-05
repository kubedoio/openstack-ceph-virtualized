#!/usr/bin/env bash
###############################################################################
# lib/hypervisors/proxmox-cloudhypervisor.sh - Hybrid Mode Implementation
#
# Hybrid backend: Cloud Hypervisor VMs running on Proxmox infrastructure
# - Uses Proxmox bridges (vmbr1199, vmbr2199)
# - Uses Cloud Hypervisor for VM execution
# - Coexists with Proxmox VMs
###############################################################################

set -euo pipefail

# Source common utilities and Cloud Hypervisor backend
HYPERVISOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HYPERVISOR_LIB_DIR/common/network.sh"
source "$HYPERVISOR_LIB_DIR/common/storage.sh"
source "$HYPERVISOR_LIB_DIR/common/cloudinit.sh"

# Load configuration
if [[ -f "$HYPERVISOR_LIB_DIR/../rook_ceph.conf" ]]; then
    source "$HYPERVISOR_LIB_DIR/../rook_ceph.conf"
fi

# Hybrid mode defaults
HYBRID_USE_PROXMOX_BRIDGES="${HYBRID_USE_PROXMOX_BRIDGES:-yes}"
HYBRID_BRIDGE_INTERNAL="${HYBRID_BRIDGE_INTERNAL:-vmbr1199}"
HYBRID_BRIDGE_EXTERNAL="${HYBRID_BRIDGE_EXTERNAL:-vmbr2199}"
HYBRID_VM_ID_START="${HYBRID_VM_ID_START:-5000}"

# Cloud Hypervisor defaults (reuse from pure CH mode)
CH_VM_DIR="${CH_VM_DIR:-/var/lib/cloud-hypervisor/vms}"
CH_IMAGE_DIR="${CH_IMAGE_DIR:-/var/lib/cloud-hypervisor/images}"
CH_API_SOCKET="${CH_API_SOCKET:-/run/cloud-hypervisor}"
CH_USE_API="${CH_USE_API:-yes}"

# Internal state
CH_VM_PIDS_FILE="/var/run/cloud-hypervisor-vms.pids"

###############################################################################
# Hybrid Mode Initialization
###############################################################################

proxmox_cloudhypervisor_init() {
    echo "INFO: Initializing Hybrid Mode (Cloud Hypervisor on Proxmox)" >&2

    # 1. Verify Proxmox is installed
    if ! command -v qm >/dev/null 2>&1; then
        echo "ERROR: Proxmox VE not found (qm command missing)" >&2
        echo "ERROR: Hybrid mode requires Proxmox VE installation" >&2
        return 1
    fi

    if ! qm list >/dev/null 2>&1; then
        echo "ERROR: Cannot execute qm commands (need root/sudo?)" >&2
        return 1
    fi

    # 2. Verify Cloud Hypervisor is available
    if ! command -v cloud-hypervisor >/dev/null 2>&1; then
        echo "ERROR: Cloud Hypervisor not installed" >&2
        echo "ERROR: Install with: curl -L https://github.com/cloud-hypervisor/... | sh" >&2
        echo "ERROR: Or run: ./setup-hybrid-mode.sh" >&2
        return 1
    fi

    # 3. Verify Proxmox bridges exist
    if ! bridge_exists "$HYBRID_BRIDGE_INTERNAL"; then
        echo "ERROR: Proxmox bridge $HYBRID_BRIDGE_INTERNAL not found" >&2
        echo "ERROR: Create it in Proxmox: Datacenter → Node → System → Network" >&2
        return 1
    fi

    if ! bridge_exists "$HYBRID_BRIDGE_EXTERNAL"; then
        echo "ERROR: Proxmox bridge $HYBRID_BRIDGE_EXTERNAL not found" >&2
        echo "ERROR: Create it in Proxmox: Datacenter → Node → System → Network" >&2
        return 1
    fi

    # 4. Create required directories
    mkdir -p "$CH_VM_DIR" "$CH_IMAGE_DIR" "$CH_API_SOCKET" 2>/dev/null || true

    # 5. Create PID tracking file if not exists
    touch "$CH_VM_PIDS_FILE" 2>/dev/null || {
        echo "WARN: Cannot create PID file, running without root?" >&2
    }

    echo "INFO: Hybrid mode ready" >&2
    echo "INFO: Using Proxmox bridges: $HYBRID_BRIDGE_INTERNAL, $HYBRID_BRIDGE_EXTERNAL" >&2
    echo "INFO: Cloud Hypervisor VMs will start at ID $HYBRID_VM_ID_START" >&2

    return 0
}

proxmox_cloudhypervisor_info() {
    # Proxmox info
    if command -v pveversion >/dev/null 2>&1; then
        local pve_version
        pve_version=$(pveversion 2>/dev/null || echo "unknown")
        echo "Proxmox VE Version: $pve_version"
    fi

    # Cloud Hypervisor info
    if command -v cloud-hypervisor >/dev/null 2>&1; then
        local ch_version
        ch_version=$(cloud-hypervisor --version 2>/dev/null | head -n1 || echo "unknown")
        echo "Cloud Hypervisor Version: $ch_version"
    fi

    # Bridge info
    echo "Bridges: $HYBRID_BRIDGE_INTERNAL, $HYBRID_BRIDGE_EXTERNAL"

    # VM count
    local vm_count=0
    if [[ -f "$CH_VM_PIDS_FILE" ]]; then
        vm_count=$(grep -c . "$CH_VM_PIDS_FILE" 2>/dev/null || echo 0)
    fi
    echo "Running Cloud Hypervisor VMs: $vm_count"

    # Proxmox VM count
    local pve_vm_count
    pve_vm_count=$(qm list | tail -n +2 | wc -l)
    echo "Running Proxmox VMs: $pve_vm_count"
}

###############################################################################
# Import Cloud Hypervisor Implementation
###############################################################################

# Source the Cloud Hypervisor backend to reuse its functions
# We'll override specific functions that need hybrid behavior
source "$HYPERVISOR_LIB_DIR/hypervisors/cloudhypervisor.sh"

# Note: Most cloudhypervisor functions are directly usable
# We only need to override network-related functions for bridge mapping

###############################################################################
# Override: Network Functions (Bridge Mapping)
###############################################################################

# Override add_network to use bridge mapping
proxmox_cloudhypervisor_add_network() {
    local vm_id="$1"
    local logical_bridge="$2"
    local mac="${3:-}"
    local model="${4:-virtio}"

    # Map logical bridge to physical Proxmox bridge
    local physical_bridge
    physical_bridge=$(map_bridge_name "$logical_bridge")

    if [[ "$physical_bridge" != "$logical_bridge" ]]; then
        echo "INFO: Mapping bridge $logical_bridge → $physical_bridge (Proxmox)" >&2
    fi

    # Verify bridge exists
    if ! bridge_exists "$physical_bridge"; then
        echo "ERROR: Bridge $physical_bridge does not exist" >&2
        return 1
    fi

    # Use Cloud Hypervisor's network implementation with mapped bridge
    cloudhypervisor_add_network "$vm_id" "$physical_bridge" "$mac" "$model"
}

# Override set_network to use bridge mapping
proxmox_cloudhypervisor_set_network() {
    local vm_id="$1"
    local net_index="$2"
    local logical_bridge="$3"
    local mac="${4:-}"
    local model="${5:-virtio}"

    # Map logical bridge to physical Proxmox bridge
    local physical_bridge
    physical_bridge=$(map_bridge_name "$logical_bridge")

    if [[ "$physical_bridge" != "$logical_bridge" ]]; then
        echo "INFO: Mapping bridge $logical_bridge → $physical_bridge (Proxmox)" >&2
    fi

    # Use Cloud Hypervisor's network implementation with mapped bridge
    cloudhypervisor_set_network "$vm_id" "$net_index" "$physical_bridge" "$mac" "$model"
}

###############################################################################
# Override: TAP Device Naming (to avoid conflicts)
###############################################################################

# Prefix TAP devices with 'ch-' to distinguish from Proxmox TAP devices
_hybrid_tap_name() {
    local vm_id="$1"
    local interface_index="$2"
    echo "tap-ch-${vm_id}-${interface_index}"
}

###############################################################################
# Delegation: Most Functions Use Cloud Hypervisor Implementation
###############################################################################

# VM Lifecycle - delegate to cloudhypervisor
proxmox_cloudhypervisor_create_vm() {
    cloudhypervisor_create_vm "$@"
}

proxmox_cloudhypervisor_start_vm() {
    cloudhypervisor_start_vm "$@"
}

proxmox_cloudhypervisor_stop_vm() {
    cloudhypervisor_stop_vm "$@"
}

proxmox_cloudhypervisor_shutdown_vm() {
    cloudhypervisor_shutdown_vm "$@"
}

proxmox_cloudhypervisor_destroy_vm() {
    cloudhypervisor_destroy_vm "$@"
}

proxmox_cloudhypervisor_vm_exists() {
    cloudhypervisor_vm_exists "$@"
}

proxmox_cloudhypervisor_vm_status() {
    cloudhypervisor_vm_status "$@"
}

proxmox_cloudhypervisor_wait_vm_running() {
    cloudhypervisor_wait_vm_running "$@"
}

# VM Configuration - delegate to cloudhypervisor
proxmox_cloudhypervisor_set_cores() {
    cloudhypervisor_set_cores "$@"
}

proxmox_cloudhypervisor_set_memory() {
    cloudhypervisor_set_memory "$@"
}

proxmox_cloudhypervisor_clone_template() {
    cloudhypervisor_clone_template "$@"
}

# Storage - delegate to cloudhypervisor
proxmox_cloudhypervisor_add_disk() {
    cloudhypervisor_add_disk "$@"
}

proxmox_cloudhypervisor_resize_disk() {
    cloudhypervisor_resize_disk "$@"
}

proxmox_cloudhypervisor_import_disk() {
    cloudhypervisor_import_disk "$@"
}

# Cloud-Init - delegate to cloudhypervisor
proxmox_cloudhypervisor_set_cloudinit() {
    cloudhypervisor_set_cloudinit "$@"
}

proxmox_cloudhypervisor_set_cloudinit_user() {
    cloudhypervisor_set_cloudinit_user "$@"
}

proxmox_cloudhypervisor_set_cloudinit_network() {
    cloudhypervisor_set_cloudinit_network "$@"
}

# Template Management - delegate to cloudhypervisor
proxmox_cloudhypervisor_create_template() {
    cloudhypervisor_create_template "$@"
}

proxmox_cloudhypervisor_create_template_from_image() {
    cloudhypervisor_create_template_from_image "$@"
}

###############################################################################
# Export Functions
###############################################################################

export -f proxmox_cloudhypervisor_init
export -f proxmox_cloudhypervisor_info

export -f proxmox_cloudhypervisor_create_vm
export -f proxmox_cloudhypervisor_start_vm
export -f proxmox_cloudhypervisor_stop_vm
export -f proxmox_cloudhypervisor_shutdown_vm
export -f proxmox_cloudhypervisor_destroy_vm
export -f proxmox_cloudhypervisor_vm_exists
export -f proxmox_cloudhypervisor_vm_status
export -f proxmox_cloudhypervisor_wait_vm_running

export -f proxmox_cloudhypervisor_set_cores
export -f proxmox_cloudhypervisor_set_memory
export -f proxmox_cloudhypervisor_clone_template

export -f proxmox_cloudhypervisor_add_network
export -f proxmox_cloudhypervisor_set_network

export -f proxmox_cloudhypervisor_add_disk
export -f proxmox_cloudhypervisor_resize_disk
export -f proxmox_cloudhypervisor_import_disk

export -f proxmox_cloudhypervisor_set_cloudinit
export -f proxmox_cloudhypervisor_set_cloudinit_user
export -f proxmox_cloudhypervisor_set_cloudinit_network

export -f proxmox_cloudhypervisor_create_template
export -f proxmox_cloudhypervisor_create_template_from_image
