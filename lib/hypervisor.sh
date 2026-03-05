#!/usr/bin/env bash
###############################################################################
# lib/hypervisor.sh - Hypervisor Abstraction Layer
#
# Provides a unified API for VM management across different hypervisors.
# Automatically detects available hypervisor or respects HYPERVISOR env/config.
#
# Supported hypervisors:
#   - proxmox: Proxmox VE (qm commands)
#   - cloudhypervisor: Cloud Hypervisor (ch-remote or REST API)
#
# Usage:
#   source lib/hypervisor.sh
#   hv_create_vm <vm_id> <name> <cores> <memory_mb>
#   hv_start_vm <vm_id>
#   hv_stop_vm <vm_id>
#   ...
###############################################################################

set -euo pipefail

# Directory containing this script
HYPERVISOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variable to store detected/configured hypervisor
HV_TYPE=""
HV_INITIALIZED=0

###############################################################################
# Hypervisor Detection
###############################################################################

# Detect available hypervisor on the system
# Priority: HYPERVISOR env var > config file > auto-detection
detect_hypervisor() {
    local config_hv="${HYPERVISOR:-auto}"

    if [[ "$config_hv" != "auto" ]]; then
        # Explicit configuration (including aliases)
        case "$config_hv" in
            proxmox|cloudhypervisor|proxmox-cloudhypervisor)
                echo "$config_hv"
                return 0
                ;;
            # Support aliases for hybrid mode
            hybrid|pve-ch)
                echo "proxmox-cloudhypervisor"
                return 0
                ;;
            *)
                echo "ERROR: Unknown hypervisor type: $config_hv" >&2
                echo "ERROR: Supported: proxmox, cloudhypervisor, proxmox-cloudhypervisor, auto" >&2
                return 1
                ;;
        esac
    fi

    # Auto-detection
    local has_proxmox=false
    local has_cloudhypervisor=false

    if command -v qm >/dev/null 2>&1; then
        if qm list >/dev/null 2>&1; then
            has_proxmox=true
        fi
    fi

    if command -v cloud-hypervisor >/dev/null 2>&1 || command -v ch-remote >/dev/null 2>&1; then
        has_cloudhypervisor=true
    fi

    # Decide based on what's available
    if [[ "$has_proxmox" == "true" && "$has_cloudhypervisor" == "true" ]]; then
        # Both available - default to Proxmox for backward compatibility
        echo "WARN: Both Proxmox and Cloud Hypervisor detected" >&2
        echo "WARN: Defaulting to 'proxmox' for backward compatibility" >&2
        echo "WARN: Set HYPERVISOR=proxmox-cloudhypervisor for hybrid mode" >&2
        echo "WARN: Set HYPERVISOR=cloudhypervisor for pure Cloud Hypervisor" >&2
        echo "proxmox"
        return 0
    elif [[ "$has_proxmox" == "true" ]]; then
        echo "proxmox"
        return 0
    elif [[ "$has_cloudhypervisor" == "true" ]]; then
        echo "cloudhypervisor"
        return 0
    fi

    echo "ERROR: No supported hypervisor detected" >&2
    echo "ERROR: Install Proxmox VE (qm) or Cloud Hypervisor (cloud-hypervisor/ch-remote)" >&2
    echo "ERROR: Or set HYPERVISOR explicitly (proxmox, cloudhypervisor, proxmox-cloudhypervisor)" >&2
    return 1
}

# Initialize hypervisor backend
hv_init() {
    if [[ $HV_INITIALIZED -eq 1 ]]; then
        return 0
    fi

    HV_TYPE=$(detect_hypervisor)
    local status=$?

    if [[ $status -ne 0 ]]; then
        return 1
    fi

    echo "INFO: Using hypervisor: $HV_TYPE" >&2

    # Load hypervisor-specific implementation
    local impl_file="$HYPERVISOR_LIB_DIR/hypervisors/${HV_TYPE}.sh"

    if [[ ! -f "$impl_file" ]]; then
        echo "ERROR: Hypervisor implementation not found: $impl_file" >&2
        return 1
    fi

    source "$impl_file"

    # Call hypervisor-specific initialization if available
    if declare -f "${HV_TYPE}_init" >/dev/null 2>&1; then
        "${HV_TYPE}_init"
    fi

    HV_INITIALIZED=1
    return 0
}

###############################################################################
# Unified API - VM Lifecycle
###############################################################################

# Create a new VM
# Args: vm_id name cores memory_mb
hv_create_vm() {
    hv_init || return 1
    "${HV_TYPE}_create_vm" "$@"
}

# Start a VM
# Args: vm_id
hv_start_vm() {
    hv_init || return 1
    "${HV_TYPE}_start_vm" "$@"
}

# Stop a VM
# Args: vm_id
hv_stop_vm() {
    hv_init || return 1
    "${HV_TYPE}_stop_vm" "$@"
}

# Shutdown a VM gracefully
# Args: vm_id
hv_shutdown_vm() {
    hv_init || return 1
    "${HV_TYPE}_shutdown_vm" "$@"
}

# Destroy/delete a VM
# Args: vm_id
hv_destroy_vm() {
    hv_init || return 1
    "${HV_TYPE}_destroy_vm" "$@"
}

# Check if VM exists
# Args: vm_id
# Returns: 0 if exists, 1 if not
hv_vm_exists() {
    hv_init || return 1
    "${HV_TYPE}_vm_exists" "$@"
}

# Get VM status
# Args: vm_id
# Returns: running, stopped, or unknown
hv_vm_status() {
    hv_init || return 1
    "${HV_TYPE}_vm_status" "$@"
}

# Wait for VM to be running
# Args: vm_id timeout_seconds
hv_wait_vm_running() {
    hv_init || return 1
    "${HV_TYPE}_wait_vm_running" "$@"
}

###############################################################################
# Unified API - VM Configuration
###############################################################################

# Set VM cores
# Args: vm_id cores
hv_set_cores() {
    hv_init || return 1
    "${HV_TYPE}_set_cores" "$@"
}

# Set VM memory
# Args: vm_id memory_mb
hv_set_memory() {
    hv_init || return 1
    "${HV_TYPE}_set_memory" "$@"
}

# Set VM to use template/clone from template
# Args: vm_id template_id
hv_clone_template() {
    hv_init || return 1
    "${HV_TYPE}_clone_template" "$@"
}

###############################################################################
# Unified API - Network
###############################################################################

# Add network interface to VM
# Args: vm_id bridge [mac] [model]
hv_add_network() {
    hv_init || return 1
    "${HV_TYPE}_add_network" "$@"
}

# Set network interface configuration
# Args: vm_id interface_index bridge [mac] [model]
hv_set_network() {
    hv_init || return 1
    "${HV_TYPE}_set_network" "$@"
}

###############################################################################
# Unified API - Storage
###############################################################################

# Add disk to VM
# Args: vm_id disk_path size_gb [disk_index]
hv_add_disk() {
    hv_init || return 1
    "${HV_TYPE}_add_disk" "$@"
}

# Resize VM disk
# Args: vm_id disk_index size_gb
hv_resize_disk() {
    hv_init || return 1
    "${HV_TYPE}_resize_disk" "$@"
}

# Import disk to VM
# Args: vm_id disk_path storage [disk_index]
hv_import_disk() {
    hv_init || return 1
    "${HV_TYPE}_import_disk" "$@"
}

###############################################################################
# Unified API - Cloud-Init
###############################################################################

# Set cloud-init configuration
# Args: vm_id cloudinit_iso_path
hv_set_cloudinit() {
    hv_init || return 1
    "${HV_TYPE}_set_cloudinit" "$@"
}

# Configure cloud-init user
# Args: vm_id username ssh_keys_file
hv_set_cloudinit_user() {
    hv_init || return 1
    "${HV_TYPE}_set_cloudinit_user" "$@"
}

# Configure cloud-init network
# Args: vm_id ip_cidr gateway
hv_set_cloudinit_network() {
    hv_init || return 1
    "${HV_TYPE}_set_cloudinit_network" "$@"
}

###############################################################################
# Unified API - Template Management
###############################################################################

# Create VM template
# Args: vm_id
hv_create_template() {
    hv_init || return 1
    "${HV_TYPE}_create_template" "$@"
}

# Download and create template from cloud image
# Args: template_id image_url
hv_create_template_from_image() {
    hv_init || return 1
    "${HV_TYPE}_create_template_from_image" "$@"
}

###############################################################################
# Utility Functions
###############################################################################

# Get hypervisor type
hv_get_type() {
    hv_init || return 1
    echo "$HV_TYPE"
}

# Check if using Proxmox
hv_is_proxmox() {
    hv_init || return 1
    [[ "$HV_TYPE" == "proxmox" ]]
}

# Check if using Cloud Hypervisor
hv_is_cloudhypervisor() {
    hv_init || return 1
    [[ "$HV_TYPE" == "cloudhypervisor" ]]
}

# Check if using Hybrid mode (Proxmox-CloudHypervisor)
hv_is_hybrid() {
    hv_init || return 1
    [[ "$HV_TYPE" == "proxmox-cloudhypervisor" ]]
}

# Check if using any Cloud Hypervisor variant (pure or hybrid)
hv_uses_cloudhypervisor() {
    hv_init || return 1
    [[ "$HV_TYPE" == "cloudhypervisor" || "$HV_TYPE" == "proxmox-cloudhypervisor" ]]
}

# Print hypervisor info
hv_info() {
    hv_init || return 1
    echo "Hypervisor Type: $HV_TYPE"

    if declare -f "${HV_TYPE}_info" >/dev/null 2>&1; then
        "${HV_TYPE}_info"
    fi
}

###############################################################################
# Export functions
###############################################################################

export -f hv_init
export -f hv_get_type
export -f hv_is_proxmox
export -f hv_is_cloudhypervisor
export -f hv_is_hybrid
export -f hv_uses_cloudhypervisor
export -f hv_info

export -f hv_create_vm
export -f hv_start_vm
export -f hv_stop_vm
export -f hv_shutdown_vm
export -f hv_destroy_vm
export -f hv_vm_exists
export -f hv_vm_status
export -f hv_wait_vm_running

export -f hv_set_cores
export -f hv_set_memory
export -f hv_clone_template

export -f hv_add_network
export -f hv_set_network

export -f hv_add_disk
export -f hv_resize_disk
export -f hv_import_disk

export -f hv_set_cloudinit
export -f hv_set_cloudinit_user
export -f hv_set_cloudinit_network

export -f hv_create_template
export -f hv_create_template_from_image
