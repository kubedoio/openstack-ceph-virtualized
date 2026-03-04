#!/usr/bin/env bash
###############################################################################
# lib/common/cloudinit.sh - Cloud-Init Utilities
#
# Generate NoCloud cloud-init ISO images with meta-data, user-data, and
# network configuration for VM provisioning.
#
# NoCloud format: https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
###############################################################################

set -euo pipefail

###############################################################################
# NoCloud ISO Generation
###############################################################################

# Generate cloud-init NoCloud ISO
# Args: output_iso_path instance_id hostname fqdn ip_cidr gateway ssh_keys_file [dns_servers]
generate_cloudinit_iso() {
    local output_iso="$1"
    local instance_id="$2"
    local hostname="$3"
    local fqdn="$4"
    local ip_cidr="$5"
    local gateway="$6"
    local ssh_keys_file="$7"
    local dns_servers="${8:-8.8.8.8,8.8.4.4}"

    # Create temporary directory for cloud-init files
    local tmpdir
    tmpdir=$(mktemp -d -t cloudinit.XXXXXX)
    trap "rm -rf '$tmpdir'" EXIT

    # Generate meta-data
    generate_metadata "$tmpdir/meta-data" "$instance_id" "$hostname" "$fqdn"

    # Generate user-data
    generate_userdata "$tmpdir/user-data" "$ssh_keys_file"

    # Generate network-config (optional, can use NoCloud v2 network config)
    generate_network_config "$tmpdir/network-config" "$ip_cidr" "$gateway" "$dns_servers"

    # Create ISO with genisoimage or mkisofs
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "$output_iso" \
            -volid cidata \
            -joliet \
            -rock \
            -input-charset utf-8 \
            "$tmpdir/meta-data" \
            "$tmpdir/user-data" \
            "$tmpdir/network-config" \
            2>/dev/null || {
            echo "ERROR: Failed to create cloud-init ISO with genisoimage" >&2
            return 1
        }
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -output "$output_iso" \
            -volid cidata \
            -joliet \
            -rock \
            -input-charset utf-8 \
            "$tmpdir/meta-data" \
            "$tmpdir/user-data" \
            "$tmpdir/network-config" \
            2>/dev/null || {
            echo "ERROR: Failed to create cloud-init ISO with mkisofs" >&2
            return 1
        }
    elif command -v xorriso >/dev/null 2>&1; then
        # Alternative: xorriso (more portable)
        xorriso -as mkisofs \
            -output "$output_iso" \
            -volid cidata \
            -joliet \
            -rock \
            -input-charset utf-8 \
            "$tmpdir/meta-data" \
            "$tmpdir/user-data" \
            "$tmpdir/network-config" \
            2>/dev/null || {
            echo "ERROR: Failed to create cloud-init ISO with xorriso" >&2
            return 1
        }
    else
        echo "ERROR: No ISO creation tool found (genisoimage, mkisofs, or xorriso)" >&2
        return 1
    fi

    echo "INFO: Cloud-init ISO created: $output_iso" >&2
    return 0
}

###############################################################################
# Meta-Data Generation
###############################################################################

# Generate cloud-init meta-data file
# Args: output_file instance_id hostname fqdn
generate_metadata() {
    local output_file="$1"
    local instance_id="$2"
    local hostname="$3"
    local fqdn="$4"

    cat > "$output_file" <<EOF
instance-id: $instance_id
local-hostname: $hostname
hostname: $hostname
fqdn: $fqdn
EOF
}

###############################################################################
# User-Data Generation
###############################################################################

# Generate cloud-init user-data file with SSH keys
# Args: output_file ssh_keys_file
generate_userdata() {
    local output_file="$1"
    local ssh_keys_file="$2"

    if [[ ! -f "$ssh_keys_file" ]]; then
        echo "ERROR: SSH keys file not found: $ssh_keys_file" >&2
        return 1
    fi

    # Start user-data with cloud-config header
    cat > "$output_file" <<'EOF'
#cloud-config

# Disable root login
disable_root: false
ssh_pwauth: false

# Default user
users:
  - name: ubuntu
    groups: [adm, sudo, cdrom, dip, plugdev, lxd]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
EOF

    # Add SSH public keys with proper indentation
    while IFS= read -r key; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        echo "      - $key" >> "$output_file"
    done < "$ssh_keys_file"

    # Add package installation and system configuration
    cat >> "$output_file" <<'EOF'

# Packages to install
packages:
  - qemu-guest-agent
  - vim
  - curl
  - wget
  - net-tools
  - htop

# Run commands on first boot
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "Cloud-init complete" > /var/log/cloudinit-done

# Set timezone
timezone: UTC

# Preserve SSH host keys
ssh_deletekeys: false
ssh_genkeytypes: []

# Do not require instance identity for SSH
ssh_svcname: ssh
EOF
}

###############################################################################
# Network Configuration Generation
###############################################################################

# Generate cloud-init network-config file (version 2)
# Args: output_file ip_cidr gateway dns_servers
generate_network_config() {
    local output_file="$1"
    local ip_cidr="$2"
    local gateway="$3"
    local dns_servers="$4"

    # Parse IP and netmask from CIDR
    local ip="${ip_cidr%/*}"
    local prefix="${ip_cidr#*/}"

    # Convert DNS servers comma-separated list to YAML array
    local dns_array=""
    IFS=',' read -ra DNS_LIST <<< "$dns_servers"
    for dns in "${DNS_LIST[@]}"; do
        dns_array+="        - $(echo "$dns" | xargs)\n"
    done

    # Network config v2 (netplan format)
    cat > "$output_file" <<EOF
version: 2
ethernets:
  eth0:
    addresses:
      - $ip_cidr
    routes:
      - to: default
        via: $gateway
    nameservers:
      addresses:
$(echo -e "$dns_array")
  ens19:
    dhcp4: false
    dhcp6: false
    optional: true
EOF
}

###############################################################################
# Simplified Cloud-Init ISO (Proxmox compatibility)
###############################################################################

# Generate simplified cloud-init ISO for Proxmox-style VMs
# Args: output_iso_path instance_id hostname ssh_keys_file
generate_simple_cloudinit_iso() {
    local output_iso="$1"
    local instance_id="$2"
    local hostname="$3"
    local ssh_keys_file="$4"

    local tmpdir
    tmpdir=$(mktemp -d -t cloudinit-simple.XXXXXX)
    trap "rm -rf '$tmpdir'" EXIT

    # Minimal meta-data
    cat > "$tmpdir/meta-data" <<EOF
instance-id: $instance_id
local-hostname: $hostname
EOF

    # Minimal user-data with just SSH keys
    cat > "$tmpdir/user-data" <<'EOF'
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
EOF

    while IFS= read -r key; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        echo "      - $key" >> "$tmpdir/user-data"
    done < "$ssh_keys_file"

    # Create ISO
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "$output_iso" -volid cidata -joliet -rock \
            "$tmpdir/meta-data" "$tmpdir/user-data" 2>/dev/null
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -output "$output_iso" -volid cidata -joliet -rock \
            "$tmpdir/meta-data" "$tmpdir/user-data" 2>/dev/null
    else
        echo "ERROR: No ISO tool available" >&2
        return 1
    fi

    return 0
}

###############################################################################
# Validation
###############################################################################

# Validate cloud-init ISO structure
# Args: iso_path
validate_cloudinit_iso() {
    local iso_path="$1"

    if [[ ! -f "$iso_path" ]]; then
        echo "ERROR: ISO file not found: $iso_path" >&2
        return 1
    fi

    # Check if ISO contains required files
    if command -v isoinfo >/dev/null 2>&1; then
        local files
        files=$(isoinfo -f -i "$iso_path" 2>/dev/null)

        if ! echo "$files" | grep -q "META-DATA"; then
            echo "ERROR: ISO missing meta-data" >&2
            return 1
        fi

        if ! echo "$files" | grep -q "USER-DATA"; then
            echo "ERROR: ISO missing user-data" >&2
            return 1
        fi

        echo "INFO: Cloud-init ISO validated successfully" >&2
        return 0
    else
        echo "WARN: isoinfo not available, skipping validation" >&2
        return 0
    fi
}

###############################################################################
# Export functions
###############################################################################

export -f generate_cloudinit_iso
export -f generate_metadata
export -f generate_userdata
export -f generate_network_config
export -f generate_simple_cloudinit_iso
export -f validate_cloudinit_iso
