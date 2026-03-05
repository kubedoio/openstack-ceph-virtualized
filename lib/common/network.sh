#!/usr/bin/env bash
###############################################################################
# lib/common/network.sh - Network Utilities
#
# Network management for hypervisors: Linux bridges, TAP devices, and
# network configuration.
###############################################################################

set -euo pipefail

###############################################################################
# Bridge Management
###############################################################################

# Create Linux bridge if it doesn't exist
# Args: bridge_name ip_cidr
create_bridge() {
    local bridge="$1"
    local ip_cidr="$2"

    # Check if bridge already exists
    if ip link show "$bridge" >/dev/null 2>&1; then
        echo "INFO: Bridge $bridge already exists" >&2
        return 0
    fi

    echo "INFO: Creating bridge: $bridge with IP $ip_cidr" >&2

    # Create bridge
    ip link add "$bridge" type bridge || {
        echo "ERROR: Failed to create bridge $bridge" >&2
        return 1
    }

    # Assign IP address
    if [[ -n "$ip_cidr" ]]; then
        ip addr add "$ip_cidr" dev "$bridge" || {
            echo "ERROR: Failed to assign IP to bridge $bridge" >&2
            return 1
        }
    fi

    # Bring bridge up
    ip link set "$bridge" up || {
        echo "ERROR: Failed to bring up bridge $bridge" >&2
        return 1
    }

    echo "INFO: Bridge $bridge created successfully" >&2
    return 0
}

# Delete Linux bridge
# Args: bridge_name
delete_bridge() {
    local bridge="$1"

    if ! ip link show "$bridge" >/dev/null 2>&1; then
        echo "INFO: Bridge $bridge does not exist" >&2
        return 0
    fi

    echo "INFO: Deleting bridge: $bridge" >&2

    # Bring bridge down
    ip link set "$bridge" down 2>/dev/null || true

    # Delete bridge
    ip link delete "$bridge" type bridge || {
        echo "ERROR: Failed to delete bridge $bridge" >&2
        return 1
    }

    echo "INFO: Bridge $bridge deleted successfully" >&2
    return 0
}

# Check if bridge exists
# Args: bridge_name
# Returns: 0 if exists, 1 if not
bridge_exists() {
    local bridge="$1"
    ip link show "$bridge" >/dev/null 2>&1
}

# List all bridges
list_bridges() {
    ip link show type bridge | grep -oP '^\d+: \K[^:]+' || true
}

###############################################################################
# TAP Device Management
###############################################################################

# Create TAP device and attach to bridge
# Args: tap_name bridge_name [owner_uid]
create_tap_device() {
    local tap="$1"
    local bridge="$2"
    local owner="${3:-}"

    # Check if TAP already exists
    if ip link show "$tap" >/dev/null 2>&1; then
        echo "INFO: TAP device $tap already exists" >&2

        # Verify it's attached to correct bridge
        local current_master
        current_master=$(ip link show "$tap" | grep -oP 'master \K\S+' || echo "")

        if [[ "$current_master" != "$bridge" ]]; then
            echo "WARN: TAP $tap attached to wrong bridge ($current_master), reattaching to $bridge" >&2
            ip link set "$tap" nomaster 2>/dev/null || true
            ip link set "$tap" master "$bridge" || {
                echo "ERROR: Failed to reattach TAP $tap to bridge $bridge" >&2
                return 1
            }
        fi

        # Ensure it's up
        ip link set "$tap" up 2>/dev/null || true
        return 0
    fi

    echo "INFO: Creating TAP device: $tap on bridge $bridge" >&2

    # Create TAP device
    if [[ -n "$owner" ]]; then
        ip tuntap add dev "$tap" mode tap user "$owner" || {
            echo "ERROR: Failed to create TAP device $tap" >&2
            return 1
        }
    else
        ip tuntap add dev "$tap" mode tap || {
            echo "ERROR: Failed to create TAP device $tap" >&2
            return 1
        }
    fi

    # Attach to bridge
    ip link set "$tap" master "$bridge" || {
        echo "ERROR: Failed to attach TAP $tap to bridge $bridge" >&2
        ip link delete "$tap" 2>/dev/null || true
        return 1
    }

    # Bring TAP device up
    ip link set "$tap" up || {
        echo "ERROR: Failed to bring up TAP device $tap" >&2
        return 1
    }

    echo "INFO: TAP device $tap created and attached to $bridge" >&2
    return 0
}

# Delete TAP device
# Args: tap_name
delete_tap_device() {
    local tap="$1"

    if ! ip link show "$tap" >/dev/null 2>&1; then
        echo "INFO: TAP device $tap does not exist" >&2
        return 0
    fi

    echo "INFO: Deleting TAP device: $tap" >&2

    # Bring down
    ip link set "$tap" down 2>/dev/null || true

    # Delete
    ip link delete "$tap" 2>/dev/null || {
        echo "ERROR: Failed to delete TAP device $tap" >&2
        return 1
    }

    echo "INFO: TAP device $tap deleted successfully" >&2
    return 0
}

# Check if TAP device exists
# Args: tap_name
# Returns: 0 if exists, 1 if not
tap_exists() {
    local tap="$1"
    ip link show "$tap" >/dev/null 2>&1
}

# List all TAP devices
list_tap_devices() {
    ip tuntap list mode tap | awk '{print $1}' | tr -d ':' || true
}

###############################################################################
# Network Configuration
###############################################################################

# Enable IP forwarding
enable_ip_forwarding() {
    echo "INFO: Enabling IP forwarding" >&2

    # Temporary
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || {
        echo "ERROR: Failed to enable IP forwarding" >&2
        return 1
    }

    # Persistent (if file exists)
    if [[ -f /etc/sysctl.conf ]]; then
        if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
            echo "INFO: IP forwarding enabled persistently in /etc/sysctl.conf" >&2
        fi
    fi

    return 0
}

# Setup NAT for bridge (masquerading)
# Args: bridge_name [external_interface]
setup_nat() {
    local bridge="$1"
    local external_iface="${2:-}"

    echo "INFO: Setting up NAT for bridge: $bridge" >&2

    # Auto-detect external interface if not provided
    if [[ -z "$external_iface" ]]; then
        external_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [[ -z "$external_iface" ]]; then
            echo "ERROR: Could not auto-detect external interface" >&2
            return 1
        fi
        echo "INFO: Auto-detected external interface: $external_iface" >&2
    fi

    # Enable IP forwarding
    enable_ip_forwarding || return 1

    # Setup iptables NAT rule (if not exists)
    if ! iptables -t nat -C POSTROUTING -s "$(get_bridge_network "$bridge")" -o "$external_iface" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$(get_bridge_network "$bridge")" -o "$external_iface" -j MASQUERADE || {
            echo "ERROR: Failed to setup NAT rule" >&2
            return 1
        }
        echo "INFO: NAT rule added for bridge $bridge" >&2
    else
        echo "INFO: NAT rule already exists for bridge $bridge" >&2
    fi

    # Accept forwarding for bridge
    if ! iptables -C FORWARD -i "$bridge" -o "$external_iface" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$bridge" -o "$external_iface" -j ACCEPT || true
    fi

    if ! iptables -C FORWARD -i "$external_iface" -o "$bridge" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$external_iface" -o "$bridge" -m state --state RELATED,ESTABLISHED -j ACCEPT || true
    fi

    echo "INFO: NAT setup complete for bridge $bridge" >&2
    return 0
}

# Get network CIDR from bridge IP
# Args: bridge_name
get_bridge_network() {
    local bridge="$1"
    ip addr show "$bridge" | grep -oP 'inet \K[\d./]+' | head -n1 || echo ""
}

###############################################################################
# Cloud Hypervisor Network Setup
###############################################################################

# Setup Cloud Hypervisor network infrastructure
# Creates internal and external bridges with proper configuration
setup_cloudhypervisor_network() {
    local internal_bridge="${1:-chbr1199}"
    local internal_ip="${2:-10.1.199.254/24}"
    local external_bridge="${3:-chbr2199}"
    local external_ip="${4:-10.2.199.254/24}"

    echo "INFO: Setting up Cloud Hypervisor network infrastructure" >&2

    # Create internal bridge (management network)
    create_bridge "$internal_bridge" "$internal_ip" || return 1

    # Create external bridge (provider network)
    create_bridge "$external_bridge" "$external_ip" || return 1

    # Enable IP forwarding
    enable_ip_forwarding || return 1

    # Setup NAT for external bridge (so VMs can reach internet)
    setup_nat "$external_bridge" || {
        echo "WARN: NAT setup failed, VMs may not have internet access" >&2
    }

    echo "INFO: Cloud Hypervisor network setup complete" >&2
    echo "INFO: Internal bridge: $internal_bridge ($internal_ip)" >&2
    echo "INFO: External bridge: $external_bridge ($external_ip)" >&2

    return 0
}

# Cleanup Cloud Hypervisor network infrastructure
cleanup_cloudhypervisor_network() {
    local internal_bridge="${1:-chbr1199}"
    local external_bridge="${2:-chbr2199}"

    echo "INFO: Cleaning up Cloud Hypervisor network infrastructure" >&2

    # Delete all TAP devices attached to bridges
    for tap in $(list_tap_devices); do
        local master
        master=$(ip link show "$tap" | grep -oP 'master \K\S+' || echo "")
        if [[ "$master" == "$internal_bridge" || "$master" == "$external_bridge" ]]; then
            delete_tap_device "$tap"
        fi
    done

    # Delete bridges
    delete_bridge "$internal_bridge" || true
    delete_bridge "$external_bridge" || true

    echo "INFO: Cloud Hypervisor network cleanup complete" >&2
    return 0
}

###############################################################################
# Utility Functions
###############################################################################

# Check if running with root/sudo privileges
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This operation requires root privileges" >&2
        echo "ERROR: Please run with sudo or as root user" >&2
        return 1
    fi
    return 0
}

# Validate bridge name
validate_bridge_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid bridge name: $name" >&2
        echo "ERROR: Bridge name must contain only alphanumeric, underscore, or dash" >&2
        return 1
    fi
    if [[ ${#name} -gt 15 ]]; then
        echo "ERROR: Bridge name too long: $name (max 15 chars)" >&2
        return 1
    fi
    return 0
}

# Validate TAP device name
validate_tap_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid TAP name: $name" >&2
        return 1
    fi
    if [[ ${#name} -gt 15 ]]; then
        echo "ERROR: TAP name too long: $name (max 15 chars)" >&2
        return 1
    fi
    return 0
}

###############################################################################
# Bridge Mapping (for Hybrid Mode)
###############################################################################

# Map logical bridge names to physical bridge names based on hypervisor type
# Args: logical_bridge_name
# Returns: physical bridge name
map_bridge_name() {
    local logical_bridge="$1"
    local hypervisor_type="${HV_TYPE:-}"

    case "$hypervisor_type" in
        proxmox-cloudhypervisor)
            # Hybrid mode: Map Cloud Hypervisor logical names to Proxmox physical names
            case "$logical_bridge" in
                chbr1199)
                    echo "${HYBRID_BRIDGE_INTERNAL:-vmbr1199}"
                    ;;
                chbr2199)
                    echo "${HYBRID_BRIDGE_EXTERNAL:-vmbr2199}"
                    ;;
                *)
                    # Pass through unmapped names
                    echo "$logical_bridge"
                    ;;
            esac
            ;;
        *)
            # Pure Proxmox or pure Cloud Hypervisor: No mapping needed
            echo "$logical_bridge"
            ;;
    esac
}

###############################################################################
# Export functions
###############################################################################

export -f create_bridge
export -f delete_bridge
export -f bridge_exists
export -f list_bridges

export -f create_tap_device
export -f delete_tap_device
export -f tap_exists
export -f list_tap_devices

export -f enable_ip_forwarding
export -f setup_nat
export -f get_bridge_network

export -f setup_cloudhypervisor_network
export -f cleanup_cloudhypervisor_network

export -f map_bridge_name

export -f check_root_privileges
export -f validate_bridge_name
export -f validate_tap_name
