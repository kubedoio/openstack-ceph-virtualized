#!/usr/bin/env bash
###############################################################################
# lib/hypervisors/proxmox.sh - Proxmox VE Implementation
#
# Hypervisor backend for Proxmox VE using qm commands.
# This is a wrapper around existing Proxmox functionality.
###############################################################################

set -euo pipefail

###############################################################################
# Proxmox-specific initialization
###############################################################################

proxmox_init() {
    # Check if qm is available
    if ! command -v qm >/dev/null 2>&1; then
        echo "ERROR: qm command not found" >&2
        echo "ERROR: This system does not appear to be a Proxmox VE node" >&2
        return 1
    fi

    # Test qm access
    if ! qm list >/dev/null 2>&1; then
        echo "ERROR: Cannot execute qm commands" >&2
        echo "ERROR: You may need root/sudo privileges" >&2
        return 1
    fi

    return 0
}

proxmox_info() {
    local pve_version
    pve_version=$(pveversion 2>/dev/null || echo "unknown")
    echo "Proxmox VE Version: $pve_version"

    local vm_count
    vm_count=$(qm list | tail -n +2 | wc -l)
    echo "Total VMs: $vm_count"
}

###############################################################################
# VM Lifecycle
###############################################################################

# Create a new VM
# Args: vm_id name cores memory_mb
proxmox_create_vm() {
    local vm_id="$1"
    local name="$2"
    local cores="$3"
    local memory_mb="$4"

    if proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id already exists" >&2
        return 1
    fi

    echo "INFO: Creating Proxmox VM $vm_id ($name)" >&2

    # Create minimal VM (will be configured further with other functions)
    qm create "$vm_id" --name "$name" --cores "$cores" --memory "$memory_mb" || {
        echo "ERROR: Failed to create VM $vm_id" >&2
        return 1
    }

    echo "INFO: VM $vm_id created successfully" >&2
    return 0
}

# Start a VM
# Args: vm_id
proxmox_start_vm() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local status
    status=$(proxmox_vm_status "$vm_id")

    if [[ "$status" == "running" ]]; then
        echo "INFO: VM $vm_id is already running" >&2
        return 0
    fi

    echo "INFO: Starting VM $vm_id" >&2
    qm start "$vm_id" || {
        echo "ERROR: Failed to start VM $vm_id" >&2
        return 1
    }

    return 0
}

# Stop a VM (forcefully)
# Args: vm_id
proxmox_stop_vm() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local status
    status=$(proxmox_vm_status "$vm_id")

    if [[ "$status" == "stopped" ]]; then
        echo "INFO: VM $vm_id is already stopped" >&2
        return 0
    fi

    echo "INFO: Stopping VM $vm_id" >&2
    qm stop "$vm_id" || {
        echo "ERROR: Failed to stop VM $vm_id" >&2
        return 1
    }

    return 0
}

# Shutdown a VM gracefully
# Args: vm_id
proxmox_shutdown_vm() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local status
    status=$(proxmox_vm_status "$vm_id")

    if [[ "$status" == "stopped" ]]; then
        echo "INFO: VM $vm_id is already stopped" >&2
        return 0
    fi

    echo "INFO: Shutting down VM $vm_id" >&2
    qm shutdown "$vm_id" || {
        echo "ERROR: Failed to shutdown VM $vm_id" >&2
        return 1
    }

    return 0
}

# Destroy/delete a VM
# Args: vm_id
proxmox_destroy_vm() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "INFO: VM $vm_id does not exist" >&2
        return 0
    fi

    echo "INFO: Destroying VM $vm_id" >&2
    qm destroy "$vm_id" --purge || {
        echo "ERROR: Failed to destroy VM $vm_id" >&2
        return 1
    }

    return 0
}

# Check if VM exists
# Args: vm_id
# Returns: 0 if exists, 1 if not
proxmox_vm_exists() {
    local vm_id="$1"
    qm list | awk '{print $1}' | grep -q "^${vm_id}$"
}

# Get VM status
# Args: vm_id
# Returns: running, stopped, or unknown
proxmox_vm_status() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "unknown"
        return 0
    fi

    local status
    status=$(qm status "$vm_id" | awk '{print $2}')

    echo "$status"
    return 0
}

# Wait for VM to be running
# Args: vm_id timeout_seconds
proxmox_wait_vm_running() {
    local vm_id="$1"
    local timeout="${2:-300}"

    echo "INFO: Waiting for VM $vm_id to be running (timeout: ${timeout}s)" >&2

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(proxmox_vm_status "$vm_id")

        if [[ "$status" == "running" ]]; then
            echo "INFO: VM $vm_id is running" >&2
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: Timeout waiting for VM $vm_id to start" >&2
    return 1
}

###############################################################################
# VM Configuration
###############################################################################

# Set VM cores
# Args: vm_id cores
proxmox_set_cores() {
    local vm_id="$1"
    local cores="$2"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    qm set "$vm_id" --cores "$cores" || {
        echo "ERROR: Failed to set cores for VM $vm_id" >&2
        return 1
    }

    return 0
}

# Set VM memory
# Args: vm_id memory_mb
proxmox_set_memory() {
    local vm_id="$1"
    local memory_mb="$2"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    qm set "$vm_id" --memory "$memory_mb" || {
        echo "ERROR: Failed to set memory for VM $vm_id" >&2
        return 1
    }

    return 0
}

# Clone from template
# Args: vm_id template_id
proxmox_clone_template() {
    local vm_id="$1"
    local template_id="$2"

    if proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id already exists" >&2
        return 1
    fi

    if ! proxmox_vm_exists "$template_id"; then
        echo "ERROR: Template $template_id does not exist" >&2
        return 1
    fi

    echo "INFO: Cloning template $template_id to VM $vm_id" >&2

    # Get VM name from config if set, otherwise use generic name
    local vm_name="vm-${vm_id}"

    qm clone "$template_id" "$vm_id" --full || {
        echo "ERROR: Failed to clone template $template_id to VM $vm_id" >&2
        return 1
    }

    echo "INFO: Template cloned successfully" >&2
    return 0
}

###############################################################################
# Network
###############################################################################

# Add network interface to VM
# Args: vm_id bridge [mac] [model]
proxmox_add_network() {
    local vm_id="$1"
    local bridge="$2"
    local mac="${3:-}"
    local model="${4:-virtio}"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Find next available net index
    local net_index=0
    while qm config "$vm_id" | grep -q "^net${net_index}:"; do
        net_index=$((net_index + 1))
    done

    local net_config="model=${model},bridge=${bridge}"
    if [[ -n "$mac" ]]; then
        net_config="${net_config},macaddr=${mac}"
    fi

    echo "INFO: Adding network interface net${net_index} to VM $vm_id (bridge: $bridge)" >&2

    qm set "$vm_id" "--net${net_index}" "$net_config" || {
        echo "ERROR: Failed to add network interface to VM $vm_id" >&2
        return 1
    }

    return 0
}

# Set network interface configuration
# Args: vm_id interface_index bridge [mac] [model]
proxmox_set_network() {
    local vm_id="$1"
    local net_index="$2"
    local bridge="$3"
    local mac="${4:-}"
    local model="${5:-virtio}"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local net_config="model=${model},bridge=${bridge}"
    if [[ -n "$mac" ]]; then
        net_config="${net_config},macaddr=${mac}"
    fi

    qm set "$vm_id" "--net${net_index}" "$net_config" || {
        echo "ERROR: Failed to set network interface net${net_index} for VM $vm_id" >&2
        return 1
    }

    return 0
}

###############################################################################
# Storage
###############################################################################

# Add disk to VM
# Args: vm_id disk_path size_gb [disk_index]
proxmox_add_disk() {
    local vm_id="$1"
    local storage="$2"  # For Proxmox, this is storage:size format (e.g., local:100)
    local size_gb="$3"
    local disk_index="${4:-}"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Auto-detect disk index if not provided
    if [[ -z "$disk_index" ]]; then
        disk_index=0
        while qm config "$vm_id" | grep -q "^scsi${disk_index}:"; do
            disk_index=$((disk_index + 1))
        done
    fi

    local disk_spec="${storage}:${size_gb}"

    echo "INFO: Adding disk scsi${disk_index} to VM $vm_id (${storage}:${size_gb}GB)" >&2

    qm set "$vm_id" "--scsi${disk_index}" "$disk_spec" || {
        echo "ERROR: Failed to add disk to VM $vm_id" >&2
        return 1
    }

    return 0
}

# Resize VM disk
# Args: vm_id disk_index size_increase
proxmox_resize_disk() {
    local vm_id="$1"
    local disk_index="$2"
    local size_increase="$3"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    echo "INFO: Resizing disk scsi${disk_index} on VM $vm_id (+${size_increase}GB)" >&2

    qm resize "$vm_id" "scsi${disk_index}" "+${size_increase}G" || {
        echo "ERROR: Failed to resize disk scsi${disk_index} on VM $vm_id" >&2
        return 1
    }

    return 0
}

# Import disk to VM
# Args: vm_id disk_path storage [disk_index]
proxmox_import_disk() {
    local vm_id="$1"
    local disk_path="$2"
    local storage="$3"
    local disk_index="${4:-0}"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk image not found: $disk_path" >&2
        return 1
    fi

    echo "INFO: Importing disk to VM $vm_id from $disk_path" >&2

    qm importdisk "$vm_id" "$disk_path" "$storage" || {
        echo "ERROR: Failed to import disk" >&2
        return 1
    }

    # The imported disk needs to be attached manually
    echo "INFO: Disk imported. Attach it with: qm set $vm_id --scsi${disk_index} ${storage}:vm-${vm_id}-disk-${disk_index}" >&2

    return 0
}

###############################################################################
# Cloud-Init
###############################################################################

# Set cloud-init configuration
# Args: vm_id cloudinit_iso_path
proxmox_set_cloudinit() {
    local vm_id="$1"
    local cloudinit_iso="$2"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Proxmox has built-in cloud-init support via ide2
    # For custom ISO, we can attach it as a CD-ROM
    echo "INFO: Attaching cloud-init ISO to VM $vm_id" >&2

    qm set "$vm_id" --ide2 "file=${cloudinit_iso},media=cdrom" || {
        echo "ERROR: Failed to attach cloud-init ISO" >&2
        return 1
    }

    return 0
}

# Configure cloud-init user
# Args: vm_id username ssh_keys_file
proxmox_set_cloudinit_user() {
    local vm_id="$1"
    local username="$2"
    local ssh_keys_file="$3"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Proxmox cloud-init integration
    qm set "$vm_id" --ciuser "$username" --sshkey "$ssh_keys_file" || {
        echo "ERROR: Failed to set cloud-init user" >&2
        return 1
    }

    return 0
}

# Configure cloud-init network
# Args: vm_id ip_cidr gateway
proxmox_set_cloudinit_network() {
    local vm_id="$1"
    local ip_cidr="$2"
    local gateway="$3"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Proxmox cloud-init network configuration
    qm set "$vm_id" --ipconfig0 "ip=${ip_cidr},gw=${gateway}" || {
        echo "ERROR: Failed to set cloud-init network config" >&2
        return 1
    }

    return 0
}

###############################################################################
# Template Management
###############################################################################

# Create VM template
# Args: vm_id
proxmox_create_template() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    echo "INFO: Converting VM $vm_id to template" >&2

    qm template "$vm_id" || {
        echo "ERROR: Failed to create template from VM $vm_id" >&2
        return 1
    }

    echo "INFO: Template created successfully" >&2
    return 0
}

# Download and create template from cloud image
# Args: template_id image_url
proxmox_create_template_from_image() {
    local template_id="$1"
    local image_url="$2"

    echo "INFO: Creating Proxmox template from cloud image not fully implemented" >&2
    echo "INFO: Please use Proxmox GUI or manual qm commands" >&2
    echo "INFO: See: https://pve.proxmox.com/wiki/Cloud-Init_Support" >&2

    return 1
}

###############################################################################
# Export functions (prefixed with proxmox_)
###############################################################################

export -f proxmox_init
export -f proxmox_info

export -f proxmox_create_vm
export -f proxmox_start_vm
export -f proxmox_stop_vm
export -f proxmox_shutdown_vm
export -f proxmox_destroy_vm
export -f proxmox_vm_exists
export -f proxmox_vm_status
export -f proxmox_wait_vm_running

export -f proxmox_set_cores
export -f proxmox_set_memory
export -f proxmox_clone_template

export -f proxmox_add_network
export -f proxmox_set_network

export -f proxmox_add_disk
export -f proxmox_resize_disk
export -f proxmox_import_disk

export -f proxmox_set_cloudinit
export -f proxmox_set_cloudinit_user
export -f proxmox_set_cloudinit_network

export -f proxmox_create_template
export -f proxmox_create_template_from_image
