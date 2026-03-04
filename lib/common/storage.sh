#!/usr/bin/env bash
###############################################################################
# lib/common/storage.sh - Storage Utilities
#
# Disk management utilities: creation, cloning, resizing, and format conversion
# for VM storage across different hypervisors.
###############################################################################

set -euo pipefail

###############################################################################
# Disk Creation
###############################################################################

# Create raw disk image (sparse)
# Args: disk_path size_gb
create_raw_disk() {
    local disk_path="$1"
    local size_gb="$2"

    if [[ -f "$disk_path" ]]; then
        echo "INFO: Disk already exists: $disk_path" >&2
        return 0
    fi

    echo "INFO: Creating raw disk: $disk_path (${size_gb}GB, sparse)" >&2

    # Ensure parent directory exists
    local disk_dir
    disk_dir=$(dirname "$disk_path")
    mkdir -p "$disk_dir"

    # Create sparse file
    truncate -s "${size_gb}G" "$disk_path" || {
        echo "ERROR: Failed to create disk: $disk_path" >&2
        return 1
    }

    echo "INFO: Raw disk created: $disk_path" >&2
    return 0
}

# Create qcow2 disk image
# Args: disk_path size_gb
create_qcow2_disk() {
    local disk_path="$1"
    local size_gb="$2"

    if [[ -f "$disk_path" ]]; then
        echo "INFO: Disk already exists: $disk_path" >&2
        return 0
    fi

    echo "INFO: Creating qcow2 disk: $disk_path (${size_gb}GB)" >&2

    # Ensure parent directory exists
    local disk_dir
    disk_dir=$(dirname "$disk_path")
    mkdir -p "$disk_dir"

    # Create qcow2 image
    qemu-img create -f qcow2 "$disk_path" "${size_gb}G" >/dev/null 2>&1 || {
        echo "ERROR: Failed to create qcow2 disk: $disk_path" >&2
        return 1
    }

    echo "INFO: qcow2 disk created: $disk_path" >&2
    return 0
}

###############################################################################
# Disk Conversion
###############################################################################

# Convert qcow2 disk to raw format
# Args: source_qcow2 dest_raw
convert_qcow2_to_raw() {
    local source="$1"
    local dest="$2"

    if [[ ! -f "$source" ]]; then
        echo "ERROR: Source disk not found: $source" >&2
        return 1
    fi

    if [[ -f "$dest" ]]; then
        echo "INFO: Destination disk already exists: $dest" >&2
        return 0
    fi

    echo "INFO: Converting qcow2 to raw: $source -> $dest" >&2

    # Ensure parent directory exists
    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    # Convert with qemu-img
    qemu-img convert -f qcow2 -O raw "$source" "$dest" || {
        echo "ERROR: Failed to convert disk" >&2
        rm -f "$dest" 2>/dev/null || true
        return 1
    }

    echo "INFO: Conversion complete: $dest" >&2
    return 0
}

# Convert raw disk to qcow2 format
# Args: source_raw dest_qcow2
convert_raw_to_qcow2() {
    local source="$1"
    local dest="$2"

    if [[ ! -f "$source" ]]; then
        echo "ERROR: Source disk not found: $source" >&2
        return 1
    fi

    if [[ -f "$dest" ]]; then
        echo "INFO: Destination disk already exists: $dest" >&2
        return 0
    fi

    echo "INFO: Converting raw to qcow2: $source -> $dest" >&2

    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    qemu-img convert -f raw -O qcow2 "$source" "$dest" || {
        echo "ERROR: Failed to convert disk" >&2
        rm -f "$dest" 2>/dev/null || true
        return 1
    }

    echo "INFO: Conversion complete: $dest" >&2
    return 0
}

###############################################################################
# Disk Cloning
###############################################################################

# Clone disk (supports both raw and qcow2)
# Args: source_disk dest_disk
clone_disk() {
    local source="$1"
    local dest="$2"

    if [[ ! -f "$source" ]]; then
        echo "ERROR: Source disk not found: $source" >&2
        return 1
    fi

    if [[ -f "$dest" ]]; then
        echo "INFO: Destination disk already exists: $dest" >&2
        return 0
    fi

    echo "INFO: Cloning disk: $source -> $dest" >&2

    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    # Detect source format
    local src_format
    src_format=$(detect_disk_format "$source")

    # Clone using qemu-img (preserves format and is efficient)
    qemu-img convert -O "$src_format" "$source" "$dest" || {
        echo "ERROR: Failed to clone disk" >&2
        rm -f "$dest" 2>/dev/null || true
        return 1
    }

    echo "INFO: Disk cloned successfully: $dest" >&2
    return 0
}

# Fast clone using copy-on-write (qcow2 backing file)
# Args: source_disk dest_disk
clone_disk_cow() {
    local source="$1"
    local dest="$2"

    if [[ ! -f "$source" ]]; then
        echo "ERROR: Source disk not found: $source" >&2
        return 1
    fi

    if [[ -f "$dest" ]]; then
        echo "INFO: Destination disk already exists: $dest" >&2
        return 0
    fi

    echo "INFO: Creating COW clone: $dest (backing file: $source)" >&2

    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    # Create qcow2 with backing file
    qemu-img create -f qcow2 -b "$source" -F qcow2 "$dest" >/dev/null 2>&1 || {
        echo "ERROR: Failed to create COW clone" >&2
        return 1
    }

    echo "INFO: COW clone created: $dest" >&2
    return 0
}

###############################################################################
# Disk Resizing
###############################################################################

# Resize disk image
# Args: disk_path new_size_gb
resize_disk() {
    local disk_path="$1"
    local new_size_gb="$2"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    echo "INFO: Resizing disk: $disk_path to ${new_size_gb}GB" >&2

    qemu-img resize "$disk_path" "${new_size_gb}G" || {
        echo "ERROR: Failed to resize disk: $disk_path" >&2
        return 1
    }

    echo "INFO: Disk resized successfully" >&2
    return 0
}

# Resize disk to specific size (absolute, not relative)
# Args: disk_path new_size_gb
resize_disk_absolute() {
    local disk_path="$1"
    local new_size_gb="$2"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    # Get current size
    local current_size_bytes
    current_size_bytes=$(qemu-img info "$disk_path" | grep "virtual size" | awk '{print $3}' | tr -d '(')

    local current_size_gb=$((current_size_bytes / 1024 / 1024 / 1024))

    if [[ $current_size_gb -ge $new_size_gb ]]; then
        echo "INFO: Disk already at or larger than target size: ${current_size_gb}GB >= ${new_size_gb}GB" >&2
        return 0
    fi

    echo "INFO: Expanding disk from ${current_size_gb}GB to ${new_size_gb}GB" >&2

    qemu-img resize "$disk_path" "${new_size_gb}G" || {
        echo "ERROR: Failed to resize disk" >&2
        return 1
    }

    echo "INFO: Disk expanded successfully" >&2
    return 0
}

###############################################################################
# Disk Information
###############################################################################

# Detect disk format (raw or qcow2)
# Args: disk_path
detect_disk_format() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    # Use qemu-img to detect format
    local format
    format=$(qemu-img info "$disk_path" | grep "file format:" | awk '{print $3}')

    if [[ -z "$format" ]]; then
        echo "ERROR: Could not detect disk format: $disk_path" >&2
        return 1
    fi

    echo "$format"
    return 0
}

# Get disk size in GB
# Args: disk_path
get_disk_size_gb() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    local size_bytes
    size_bytes=$(qemu-img info "$disk_path" | grep "virtual size:" | awk '{print $3}' | tr -d '(')

    if [[ -z "$size_bytes" ]]; then
        echo "ERROR: Could not get disk size: $disk_path" >&2
        return 1
    fi

    echo $((size_bytes / 1024 / 1024 / 1024))
    return 0
}

# Get disk actual size (allocated) in GB
# Args: disk_path
get_disk_actual_size_gb() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    local size_bytes
    size_bytes=$(du -b "$disk_path" | awk '{print $1}')

    echo $((size_bytes / 1024 / 1024 / 1024))
    return 0
}

# Print disk information
# Args: disk_path
disk_info() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    echo "Disk: $disk_path"
    qemu-img info "$disk_path"
    return 0
}

###############################################################################
# Cloud Image Download
###############################################################################

# Download Ubuntu cloud image
# Args: output_path [release]
download_ubuntu_cloud_image() {
    local output_path="$1"
    local release="${2:-noble}"  # Default to Ubuntu 24.04 (Noble)

    if [[ -f "$output_path" ]]; then
        echo "INFO: Cloud image already exists: $output_path" >&2
        return 0
    fi

    local image_url="https://cloud-images.ubuntu.com/${release}/current/${release}-server-cloudimg-amd64.img"

    echo "INFO: Downloading Ubuntu ${release} cloud image" >&2
    echo "INFO: URL: $image_url" >&2

    local output_dir
    output_dir=$(dirname "$output_path")
    mkdir -p "$output_dir"

    # Download with curl or wget
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$output_path" "$image_url" || {
            echo "ERROR: Failed to download cloud image" >&2
            rm -f "$output_path" 2>/dev/null || true
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output_path" "$image_url" || {
            echo "ERROR: Failed to download cloud image" >&2
            rm -f "$output_path" 2>/dev/null || true
            return 1
        }
    else
        echo "ERROR: Neither curl nor wget found" >&2
        return 1
    fi

    echo "INFO: Cloud image downloaded: $output_path" >&2
    return 0
}

###############################################################################
# Template Management
###############################################################################

# Create VM template from cloud image
# Args: template_path cloud_image_path
create_template_from_cloud_image() {
    local template_path="$1"
    local cloud_image_path="$2"

    if [[ ! -f "$cloud_image_path" ]]; then
        echo "ERROR: Cloud image not found: $cloud_image_path" >&2
        return 1
    fi

    if [[ -f "$template_path" ]]; then
        echo "INFO: Template already exists: $template_path" >&2
        return 0
    fi

    echo "INFO: Creating template from cloud image" >&2

    # Detect source format
    local src_format
    src_format=$(detect_disk_format "$cloud_image_path")

    # Convert to raw if needed (Cloud Hypervisor prefers raw)
    if [[ "$src_format" == "qcow2" ]]; then
        echo "INFO: Converting qcow2 template to raw format" >&2
        convert_qcow2_to_raw "$cloud_image_path" "$template_path" || return 1
    else
        echo "INFO: Copying raw template" >&2
        clone_disk "$cloud_image_path" "$template_path" || return 1
    fi

    echo "INFO: Template created: $template_path" >&2
    return 0
}

###############################################################################
# Disk Cleanup
###############################################################################

# Delete disk image
# Args: disk_path
delete_disk() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "INFO: Disk does not exist: $disk_path" >&2
        return 0
    fi

    echo "INFO: Deleting disk: $disk_path" >&2

    rm -f "$disk_path" || {
        echo "ERROR: Failed to delete disk: $disk_path" >&2
        return 1
    }

    echo "INFO: Disk deleted: $disk_path" >&2
    return 0
}

# Cleanup COW chain (flatten qcow2 with backing file)
# Args: disk_path
flatten_disk() {
    local disk_path="$1"

    if [[ ! -f "$disk_path" ]]; then
        echo "ERROR: Disk not found: $disk_path" >&2
        return 1
    fi

    local format
    format=$(detect_disk_format "$disk_path")

    if [[ "$format" != "qcow2" ]]; then
        echo "INFO: Disk is not qcow2, no flattening needed" >&2
        return 0
    fi

    # Check if has backing file
    local backing_file
    backing_file=$(qemu-img info "$disk_path" | grep "backing file:" | cut -d: -f2- | xargs || echo "")

    if [[ -z "$backing_file" ]]; then
        echo "INFO: Disk has no backing file, already flat" >&2
        return 0
    fi

    echo "INFO: Flattening disk: $disk_path (backing: $backing_file)" >&2

    local temp_flat="${disk_path}.flat.tmp"

    qemu-img convert -O qcow2 "$disk_path" "$temp_flat" || {
        echo "ERROR: Failed to flatten disk" >&2
        rm -f "$temp_flat" 2>/dev/null || true
        return 1
    }

    mv "$temp_flat" "$disk_path" || {
        echo "ERROR: Failed to replace disk with flattened version" >&2
        return 1
    }

    echo "INFO: Disk flattened successfully" >&2
    return 0
}

###############################################################################
# Export functions
###############################################################################

export -f create_raw_disk
export -f create_qcow2_disk
export -f convert_qcow2_to_raw
export -f convert_raw_to_qcow2
export -f clone_disk
export -f clone_disk_cow
export -f resize_disk
export -f resize_disk_absolute
export -f detect_disk_format
export -f get_disk_size_gb
export -f get_disk_actual_size_gb
export -f disk_info
export -f download_ubuntu_cloud_image
export -f create_template_from_cloud_image
export -f delete_disk
export -f flatten_disk
