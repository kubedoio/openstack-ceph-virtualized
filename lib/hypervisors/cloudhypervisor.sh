#!/usr/bin/env bash
###############################################################################
# lib/hypervisors/cloudhypervisor.sh - Cloud Hypervisor Implementation
#
# Hypervisor backend for Cloud Hypervisor using ch-remote CLI or REST API.
# Provides full feature parity with Proxmox implementation.
###############################################################################

set -euo pipefail

# Source common utilities
HYPERVISOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HYPERVISOR_LIB_DIR/common/network.sh"
source "$HYPERVISOR_LIB_DIR/common/storage.sh"
source "$HYPERVISOR_LIB_DIR/common/cloudinit.sh"

# Load configuration
if [[ -f "$HYPERVISOR_LIB_DIR/../rook_ceph.conf" ]]; then
    source "$HYPERVISOR_LIB_DIR/../rook_ceph.conf"
fi

# Cloud Hypervisor defaults
CH_VM_DIR="${CH_VM_DIR:-/var/lib/cloud-hypervisor/vms}"
CH_IMAGE_DIR="${CH_IMAGE_DIR:-/var/lib/cloud-hypervisor/images}"
CH_API_SOCKET="${CH_API_SOCKET:-/run/cloud-hypervisor}"
CH_USE_API="${CH_USE_API:-yes}"

# Internal state
CH_VM_PIDS_FILE="/var/run/cloud-hypervisor-vms.pids"

###############################################################################
# Cloud Hypervisor initialization
###############################################################################

cloudhypervisor_init() {
    # Check for Cloud Hypervisor binary
    if ! command -v cloud-hypervisor >/dev/null 2>&1 && ! command -v ch-remote >/dev/null 2>&1; then
        echo "ERROR: Cloud Hypervisor not found" >&2
        echo "ERROR: Install cloud-hypervisor or ch-remote" >&2
        return 1
    fi

    # Create required directories
    mkdir -p "$CH_VM_DIR" "$CH_IMAGE_DIR" "$CH_API_SOCKET"

    # Create PID tracking file if not exists
    touch "$CH_VM_PIDS_FILE" 2>/dev/null || {
        echo "WARN: Cannot create PID file, running without root?" >&2
    }

    # Setup network bridges (required for CH VMs)
    echo "INFO: Ensuring Cloud Hypervisor network bridges exist" >&2
    setup_cloudhypervisor_network 2>/dev/null || {
        echo "WARN: Failed to setup network bridges (may need sudo)" >&2
    }

    return 0
}

cloudhypervisor_info() {
    if command -v cloud-hypervisor >/dev/null 2>&1; then
        local ch_version
        ch_version=$(cloud-hypervisor --version 2>/dev/null || echo "unknown")
        echo "Cloud Hypervisor Version: $ch_version"
    fi

    local vm_count=0
    if [[ -f "$CH_VM_PIDS_FILE" ]]; then
        vm_count=$(grep -c . "$CH_VM_PIDS_FILE" 2>/dev/null || echo 0)
    fi
    echo "Running VMs: $vm_count"
}

###############################################################################
# VM State Management
###############################################################################

# Get VM directory
_ch_vm_dir() {
    local vm_id="$1"
    echo "${CH_VM_DIR}/vm-${vm_id}"
}

# Get VM config file
_ch_vm_config() {
    local vm_id="$1"
    echo "$(_ch_vm_dir "$vm_id")/config.json"
}

# Get VM PID file
_ch_vm_pidfile() {
    local vm_id="$1"
    echo "$(_ch_vm_dir "$vm_id")/vm.pid"
}

# Get VM API socket
_ch_vm_socket() {
    local vm_id="$1"
    echo "${CH_API_SOCKET}/vm-${vm_id}.sock"
}

# Check if VM is tracked
_ch_vm_tracked() {
    local vm_id="$1"
    [[ -d "$(_ch_vm_dir "$vm_id")" ]]
}

# Get VM PID
_ch_vm_pid() {
    local vm_id="$1"
    local pidfile
    pidfile=$(_ch_vm_pidfile "$vm_id")

    if [[ -f "$pidfile" ]]; then
        cat "$pidfile" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Check if VM process is running
_ch_vm_is_running() {
    local vm_id="$1"
    local pid
    pid=$(_ch_vm_pid "$vm_id")

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

###############################################################################
# VM Lifecycle
###############################################################################

# Create a new VM
# Args: vm_id name cores memory_mb
cloudhypervisor_create_vm() {
    local vm_id="$1"
    local name="$2"
    local cores="$3"
    local memory_mb="$4"

    if _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id already exists" >&2
        return 1
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    echo "INFO: Creating Cloud Hypervisor VM $vm_id ($name)" >&2

    # Create VM directory
    mkdir -p "$vm_dir"

    # Create basic config
    cat > "$(_ch_vm_config "$vm_id")" <<EOF
{
  "vm_id": "$vm_id",
  "name": "$name",
  "cpus": {
    "boot_vcpus": $cores,
    "max_vcpus": $cores
  },
  "memory": {
    "size": $((memory_mb * 1024 * 1024))
  },
  "disks": [],
  "net": []
}
EOF

    echo "INFO: VM $vm_id created (not started)" >&2
    return 0
}

# Start a VM
# Args: vm_id
cloudhypervisor_start_vm() {
    local vm_id="$1"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    if _ch_vm_is_running "$vm_id"; then
        echo "INFO: VM $vm_id is already running" >&2
        return 0
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    local api_socket
    api_socket=$(_ch_vm_socket "$vm_id")

    local pidfile
    pidfile=$(_ch_vm_pidfile "$vm_id")

    # Build cloud-hypervisor command from config
    echo "INFO: Starting VM $vm_id with Cloud Hypervisor" >&2

    # Parse config to build command
    local cpus memory_mb
    cpus=$(jq -r '.cpus.boot_vcpus' "$config_file")
    memory_mb=$(($(jq -r '.memory.size' "$config_file") / 1024 / 1024))

    # Get disks - Cloud Hypervisor expects comma-separated paths in single --disk argument
    local disk_paths=()
    local disk_count
    disk_count=$(jq -r '.disks | length' "$config_file")
    for ((i=0; i<disk_count; i++)); do
        local disk_path
        disk_path=$(jq -r ".disks[$i].path" "$config_file")
        local disk_readonly
        disk_readonly=$(jq -r ".disks[$i].readonly // false" "$config_file")

        if [[ -f "$disk_path" ]]; then
            if [[ "$disk_readonly" == "true" ]]; then
                disk_paths+=("path=${disk_path},readonly=on")
            else
                disk_paths+=("path=${disk_path}")
            fi
        fi
    done

    # Construct disk argument
    local disk_arg=""
    if [[ ${#disk_paths[@]} -gt 0 ]]; then
        # Join paths with space (each path= is a separate disk)
        disk_arg="--disk $(IFS=' ' ; echo "${disk_paths[*]}")"
    fi

    # Get network interfaces (TAP devices) - similar format as disks
    local net_paths=()
    local net_count
    net_count=$(jq -r '.net | length' "$config_file")
    for ((i=0; i<net_count; i++)); do
        local tap_name
        tap_name=$(jq -r ".net[$i].tap" "$config_file")
        if [[ -n "$tap_name" ]]; then
            # Ensure TAP device exists
            local bridge
            bridge=$(jq -r ".net[$i].bridge" "$config_file")
            create_tap_device "$tap_name" "$bridge" 2>/dev/null || true
            local mac
            mac=$(jq -r ".net[$i].mac" "$config_file")
            net_paths+=("tap=${tap_name},mac=${mac}")
        fi
    done

    # Construct network argument
    local net_arg=""
    if [[ ${#net_paths[@]} -gt 0 ]]; then
        net_arg="--net $(IFS=' ' ; echo "${net_paths[*]}")"
    fi

    # Check for kernel/initrd (for direct kernel boot)
    local kernel_path="${vm_dir}/vmlinuz"
    local kernel_args=""
    if [[ ! -f "$kernel_path" ]]; then
        # Use firmware boot (default for cloud images)
        kernel_args=""
    fi

    # Launch Cloud Hypervisor
    # Note: Use eval to properly expand the disk_arg and net_arg strings
    eval cloud-hypervisor \
        --api-socket "$api_socket" \
        --cpus "boot=${cpus}" \
        --memory "size=${memory_mb}M" \
        $disk_arg \
        $net_arg \
        --serial tty \
        --console off \
        2>"${vm_dir}/console.log" &

    local ch_pid=$!

    # Save PID
    echo "$ch_pid" > "$pidfile"

    # Wait briefly for process to stabilize
    sleep 2

    if ! kill -0 "$ch_pid" 2>/dev/null; then
        echo "ERROR: Cloud Hypervisor process died immediately" >&2
        echo "ERROR: Check logs at: ${vm_dir}/console.log" >&2
        return 1
    fi

    # Send boot command via API
    if command -v ch-remote >/dev/null 2>&1; then
        ch-remote --api-socket "$api_socket" boot 2>/dev/null || {
            echo "WARN: Failed to send boot command via API" >&2
        }
    fi

    echo "INFO: VM $vm_id started (PID: $ch_pid)" >&2
    return 0
}

# Stop a VM (forcefully)
# Args: vm_id
cloudhypervisor_stop_vm() {
    local vm_id="$1"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    if ! _ch_vm_is_running "$vm_id"; then
        echo "INFO: VM $vm_id is not running" >&2
        return 0
    fi

    echo "INFO: Stopping VM $vm_id" >&2

    local pid
    pid=$(_ch_vm_pid "$vm_id")

    # Try API shutdown first
    local api_socket
    api_socket=$(_ch_vm_socket "$vm_id")

    if command -v ch-remote >/dev/null 2>&1 && [[ -S "$api_socket" ]]; then
        ch-remote --api-socket "$api_socket" shutdown 2>/dev/null || true
        sleep 2
    fi

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2

        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi

    # Clean up PID file
    rm -f "$(_ch_vm_pidfile "$vm_id")"

    echo "INFO: VM $vm_id stopped" >&2
    return 0
}

# Shutdown a VM gracefully
# Args: vm_id
cloudhypervisor_shutdown_vm() {
    cloudhypervisor_stop_vm "$@"
}

# Destroy/delete a VM
# Args: vm_id
cloudhypervisor_destroy_vm() {
    local vm_id="$1"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "INFO: VM $vm_id does not exist" >&2
        return 0
    fi

    # Stop if running
    if _ch_vm_is_running "$vm_id"; then
        cloudhypervisor_stop_vm "$vm_id"
    fi

    echo "INFO: Destroying VM $vm_id" >&2

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    # Clean up TAP devices
    local config_file="$(_ch_vm_config "$vm_id")"
    if [[ -f "$config_file" ]]; then
        local net_count
        net_count=$(jq -r '.net | length' "$config_file" 2>/dev/null || echo 0)
        for ((i=0; i<net_count; i++)); do
            local tap_name
            tap_name=$(jq -r ".net[$i].tap" "$config_file" 2>/dev/null || echo "")
            if [[ -n "$tap_name" ]]; then
                delete_tap_device "$tap_name" 2>/dev/null || true
            fi
        done
    fi

    # Remove VM directory
    rm -rf "$vm_dir"

    echo "INFO: VM $vm_id destroyed" >&2
    return 0
}

# Check if VM exists
# Args: vm_id
cloudhypervisor_vm_exists() {
    local vm_id="$1"
    _ch_vm_tracked "$vm_id"
}

# Get VM status
# Args: vm_id
cloudhypervisor_vm_status() {
    local vm_id="$1"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "unknown"
        return 0
    fi

    if _ch_vm_is_running "$vm_id"; then
        echo "running"
    else
        echo "stopped"
    fi

    return 0
}

# Wait for VM to be running
# Args: vm_id timeout_seconds
cloudhypervisor_wait_vm_running() {
    local vm_id="$1"
    local timeout="${2:-300}"

    echo "INFO: Waiting for VM $vm_id to be running (timeout: ${timeout}s)" >&2

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if _ch_vm_is_running "$vm_id"; then
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
cloudhypervisor_set_cores() {
    local vm_id="$1"
    local cores="$2"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    # Update config
    jq ".cpus.boot_vcpus = $cores | .cpus.max_vcpus = $cores" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    return 0
}

# Set VM memory
# Args: vm_id memory_mb
cloudhypervisor_set_memory() {
    local vm_id="$1"
    local memory_mb="$2"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    local memory_bytes=$((memory_mb * 1024 * 1024))

    # Update config
    jq ".memory.size = $memory_bytes" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    return 0
}

# Clone from template
# Args: vm_id template_id
cloudhypervisor_clone_template() {
    local vm_id="$1"
    local template_id="$2"

    # For Cloud Hypervisor, template is just a base disk image
    local template_disk="${CH_IMAGE_DIR}/template-${template_id}.raw"

    if [[ ! -f "$template_disk" ]]; then
        echo "ERROR: Template disk not found: $template_disk" >&2
        return 1
    fi

    if _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id already exists" >&2
        return 1
    fi

    echo "INFO: Cloning template $template_id to VM $vm_id" >&2

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")
    mkdir -p "$vm_dir"

    # Clone template disk as VM's system disk
    local vm_disk="${vm_dir}/system.raw"
    clone_disk "$template_disk" "$vm_disk" || return 1

    # Resize to 50GB (expand from base)
    resize_disk_absolute "$vm_disk" 50 || return 1

    # Create initial config
    cat > "$(_ch_vm_config "$vm_id")" <<EOF
{
  "vm_id": "$vm_id",
  "name": "vm-${vm_id}",
  "cpus": {
    "boot_vcpus": 4,
    "max_vcpus": 4
  },
  "memory": {
    "size": $((8192 * 1024 * 1024))
  },
  "disks": [
    {
      "path": "${vm_disk}",
      "readonly": false
    }
  ],
  "net": []
}
EOF

    echo "INFO: Template cloned successfully" >&2
    return 0
}

###############################################################################
# Network
###############################################################################

# Generate random MAC address
_generate_mac() {
    printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

# Add network interface to VM
# Args: vm_id bridge [mac] [model]
cloudhypervisor_add_network() {
    local vm_id="$1"
    local bridge="$2"
    local mac="${3:-$(_generate_mac)}"
    local model="${4:-virtio}"  # Cloud Hypervisor only supports virtio

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    # Determine TAP device name
    local net_count
    net_count=$(jq -r '.net | length' "$config_file")
    local tap_name="tap-${vm_id}-${net_count}"

    # Create TAP device
    create_tap_device "$tap_name" "$bridge" || return 1

    # Add to config
    local net_entry
    net_entry=$(jq -n \
        --arg tap "$tap_name" \
        --arg bridge "$bridge" \
        --arg mac "$mac" \
        '{tap: $tap, bridge: $bridge, mac: $mac}')

    jq ".net += [$net_entry]" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    echo "INFO: Network interface added to VM $vm_id (bridge: $bridge, tap: $tap_name)" >&2
    return 0
}

# Set network interface configuration
# Args: vm_id interface_index bridge [mac] [model]
cloudhypervisor_set_network() {
    local vm_id="$1"
    local net_index="$2"
    local bridge="$3"
    local mac="${4:-$(_generate_mac)}"
    local model="${5:-virtio}"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    local tap_name="tap-${vm_id}-${net_index}"

    # Delete old TAP if exists
    local old_tap
    old_tap=$(jq -r ".net[$net_index].tap // empty" "$config_file")
    if [[ -n "$old_tap" ]]; then
        delete_tap_device "$old_tap" 2>/dev/null || true
    fi

    # Create new TAP
    create_tap_device "$tap_name" "$bridge" || return 1

    # Update config
    jq ".net[$net_index] = {tap: \"$tap_name\", bridge: \"$bridge\", mac: \"$mac\"}" \
        "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    return 0
}

###############################################################################
# Storage
###############################################################################

# Add disk to VM
# Args: vm_id disk_size_gb [disk_index]
cloudhypervisor_add_disk() {
    local vm_id="$1"
    local disk_size_gb="$2"
    local disk_index="${3:-}"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    # Determine disk index
    if [[ -z "$disk_index" ]]; then
        disk_index=$(jq -r '.disks | length' "$config_file")
    fi

    # Create disk
    local disk_path="${vm_dir}/disk-${disk_index}.raw"
    create_raw_disk "$disk_path" "$disk_size_gb" || return 1

    # Add to config
    local disk_entry
    disk_entry=$(jq -n --arg path "$disk_path" '{path: $path, readonly: false}')

    jq ".disks += [$disk_entry]" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    echo "INFO: Disk added to VM $vm_id: $disk_path (${disk_size_gb}GB)" >&2
    return 0
}

# Resize VM disk
# Args: vm_id disk_index size_increase_gb
cloudhypervisor_resize_disk() {
    local vm_id="$1"
    local disk_index="$2"
    local size_increase_gb="$3"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    local disk_path
    disk_path=$(jq -r ".disks[$disk_index].path" "$config_file")

    if [[ -z "$disk_path" || "$disk_path" == "null" ]]; then
        echo "ERROR: Disk index $disk_index not found" >&2
        return 1
    fi

    resize_disk "$disk_path" "+${size_increase_gb}" || return 1

    echo "INFO: Disk resized: $disk_path (+${size_increase_gb}GB)" >&2
    return 0
}

# Import disk to VM
# Args: vm_id disk_path [disk_index]
cloudhypervisor_import_disk() {
    local vm_id="$1"
    local source_disk="$2"
    local disk_index="${3:-}"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    if [[ -z "$disk_index" ]]; then
        disk_index=$(jq -r '.disks | length' "$config_file")
    fi

    local dest_disk="${vm_dir}/disk-${disk_index}.raw"

    # Clone disk
    clone_disk "$source_disk" "$dest_disk" || return 1

    # Add to config
    local disk_entry
    disk_entry=$(jq -n --arg path "$dest_disk" '{path: $path, readonly: false}')

    jq ".disks += [$disk_entry]" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    echo "INFO: Disk imported to VM $vm_id: $dest_disk" >&2
    return 0
}

###############################################################################
# Cloud-Init
###############################################################################

# Set cloud-init configuration
# Args: vm_id cloudinit_iso_path
cloudhypervisor_set_cloudinit() {
    local vm_id="$1"
    local cloudinit_iso="$2"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    local target_iso="${vm_dir}/cloudinit.iso"

    # Only copy if source and destination are different
    if [[ "$cloudinit_iso" != "$target_iso" ]]; then
        cp "$cloudinit_iso" "$target_iso" || {
            echo "ERROR: Failed to copy cloud-init ISO" >&2
            return 1
        }
    fi

    # Add as readonly disk
    local config_file
    config_file=$(_ch_vm_config "$vm_id")

    # Check if cloudinit ISO is already in config
    if jq -e '.disks[] | select(.path == "'"$target_iso"'")' "$config_file" >/dev/null 2>&1; then
        echo "INFO: Cloud-init ISO already attached to VM $vm_id" >&2
        return 0
    fi

    local disk_entry
    disk_entry=$(jq -n --arg path "$target_iso" '{path: $path, readonly: true}')

    jq ".disks += [$disk_entry]" "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    echo "INFO: Cloud-init ISO attached to VM $vm_id" >&2
    return 0
}

# Configure cloud-init user (generates ISO)
# Args: vm_id username ssh_keys_file
cloudhypervisor_set_cloudinit_user() {
    local vm_id="$1"
    local username="$2"
    local ssh_keys_file="$3"

    # This is handled by generate_cloudinit_iso
    # Store for later use
    echo "$username" > "$(_ch_vm_dir "$vm_id")/.cloudinit_user"
    echo "$ssh_keys_file" > "$(_ch_vm_dir "$vm_id")/.cloudinit_keys"

    return 0
}

# Configure cloud-init network (generates ISO)
# Args: vm_id ip_cidr gateway
cloudhypervisor_set_cloudinit_network() {
    local vm_id="$1"
    local ip_cidr="$2"
    local gateway="$3"

    # Store for ISO generation
    echo "$ip_cidr" > "$(_ch_vm_dir "$vm_id")/.cloudinit_ip"
    echo "$gateway" > "$(_ch_vm_dir "$vm_id")/.cloudinit_gw"

    return 0
}

###############################################################################
# Template Management
###############################################################################

# Create VM template
# Args: vm_id
cloudhypervisor_create_template() {
    local vm_id="$1"

    if ! _ch_vm_tracked "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Stop VM if running
    if _ch_vm_is_running "$vm_id"; then
        cloudhypervisor_stop_vm "$vm_id"
    fi

    local vm_dir
    vm_dir=$(_ch_vm_dir "$vm_id")

    local system_disk="${vm_dir}/system.raw"
    local template_disk="${CH_IMAGE_DIR}/template-${vm_id}.raw"

    if [[ ! -f "$system_disk" ]]; then
        echo "ERROR: System disk not found: $system_disk" >&2
        return 1
    fi

    echo "INFO: Creating template from VM $vm_id" >&2

    # Copy system disk as template
    cp "$system_disk" "$template_disk" || return 1

    echo "INFO: Template created: $template_disk" >&2
    return 0
}

# Download and create template from cloud image
# Args: template_id image_url
cloudhypervisor_create_template_from_image() {
    local template_id="$1"
    local image_url="${2:-}"

    local template_disk="${CH_IMAGE_DIR}/template-${template_id}.raw"

    if [[ -f "$template_disk" ]]; then
        echo "INFO: Template already exists: $template_disk" >&2
        return 0
    fi

    echo "INFO: Creating template $template_id from cloud image" >&2

    # Download Ubuntu cloud image
    local cloud_image="${CH_IMAGE_DIR}/ubuntu-cloud.qcow2"
    download_ubuntu_cloud_image "$cloud_image" noble || return 1

    # Convert to raw format
    convert_qcow2_to_raw "$cloud_image" "$template_disk" || return 1

    echo "INFO: Template created: $template_disk" >&2
    return 0
}

###############################################################################
# Export functions
###############################################################################

export -f cloudhypervisor_init
export -f cloudhypervisor_info

export -f cloudhypervisor_create_vm
export -f cloudhypervisor_start_vm
export -f cloudhypervisor_stop_vm
export -f cloudhypervisor_shutdown_vm
export -f cloudhypervisor_destroy_vm
export -f cloudhypervisor_vm_exists
export -f cloudhypervisor_vm_status
export -f cloudhypervisor_wait_vm_running

export -f cloudhypervisor_set_cores
export -f cloudhypervisor_set_memory
export -f cloudhypervisor_clone_template

export -f cloudhypervisor_add_network
export -f cloudhypervisor_set_network

export -f cloudhypervisor_add_disk
export -f cloudhypervisor_resize_disk
export -f cloudhypervisor_import_disk

export -f cloudhypervisor_set_cloudinit
export -f cloudhypervisor_set_cloudinit_user
export -f cloudhypervisor_set_cloudinit_network

export -f cloudhypervisor_create_template
export -f cloudhypervisor_create_template_from_image
