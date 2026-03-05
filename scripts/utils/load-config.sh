#!/usr/bin/env bash
###############################################################################
# scripts/utils/load-config.sh - Configuration Loader
#
# Loads configuration files in the correct order:
# 1. config/default.conf (common settings)
# 2. Hypervisor-specific config based on HYPERVISOR variable
# 3. Fallback to old rook_ceph.conf if new configs don't exist
#
# Usage:
#   source scripts/utils/load-config.sh
#
# Environment Variables:
#   HYPERVISOR - Hypervisor type (auto, proxmox, cloudhypervisor, proxmox-cloudhypervisor)
#   CONFIG_FILE - Override config file path (optional)
###############################################################################

# Determine script directory
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$UTILS_DIR/../.." && pwd)"
else
    # Fallback if BASH_SOURCE not available
    PROJECT_ROOT="$(pwd)"
fi

# Configuration directory
CONFIG_DIR="${PROJECT_ROOT}/config"

# Color output for messages
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
else
    RED=''
    YELLOW=''
    GREEN=''
    NC=''
fi

# Logging functions
config_info() {
    echo -e "${GREEN}[CONFIG]${NC} $*" >&2
}

config_warn() {
    echo -e "${YELLOW}[CONFIG WARN]${NC} $*" >&2
}

config_error() {
    echo -e "${RED}[CONFIG ERROR]${NC} $*" >&2
}

###############################################################################
# Main Configuration Loading
###############################################################################

load_configuration() {
    local loaded_default=false
    local loaded_hypervisor=false
    local used_legacy=false

    # If CONFIG_FILE is explicitly set, use only that file
    if [[ -n "${CONFIG_FILE:-}" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            config_info "Loading config from: $CONFIG_FILE"
            source "$CONFIG_FILE"
            return 0
        else
            config_error "CONFIG_FILE specified but not found: $CONFIG_FILE"
            return 1
        fi
    fi

    # Preserve HYPERVISOR if already set in environment
    local env_hypervisor="${HYPERVISOR:-}"

    # Check if new config structure exists
    if [[ -f "$CONFIG_DIR/default.conf" ]]; then
        # Load default configuration (common settings)
        config_info "Loading default configuration"
        source "$CONFIG_DIR/default.conf"
        loaded_default=true

        # Determine hypervisor type (environment overrides config file)
        local hv_type="${env_hypervisor:-${HYPERVISOR:-auto}}"

        # If env had a value, restore it (takes precedence over config file)
        if [[ -n "$env_hypervisor" ]]; then
            HYPERVISOR="$env_hypervisor"
        fi

        # Normalize hypervisor type (handle aliases)
        case "$hv_type" in
            hybrid|pve-ch)
                hv_type="proxmox-cloudhypervisor"
                ;;
        esac

        # If auto-detect, don't load hypervisor-specific config yet
        # (Let hypervisor.sh handle detection)
        if [[ "$hv_type" != "auto" ]]; then
            # Map hypervisor type to config filename
            local hv_config_name=""
            case "$hv_type" in
                proxmox)
                    hv_config_name="proxmox"
                    ;;
                cloudhypervisor)
                    hv_config_name="cloudhypervisor"
                    ;;
                proxmox-cloudhypervisor)
                    hv_config_name="hybrid"
                    ;;
                *)
                    config_warn "Unknown hypervisor type: $hv_type"
                    ;;
            esac

            # Load hypervisor-specific config if it exists
            if [[ -n "$hv_config_name" ]]; then
                local hv_config_file="$CONFIG_DIR/${hv_config_name}.conf"

                if [[ -f "$hv_config_file" ]]; then
                    config_info "Loading $hv_type configuration"
                    source "$hv_config_file"
                    loaded_hypervisor=true
                else
                    # Check if example exists
                    local example_file="$CONFIG_DIR/examples/${hv_config_name}.conf"
                    if [[ -f "$example_file" ]]; then
                        config_warn "Hypervisor config not found: $hv_config_file"
                        config_warn "Copy example: cp $example_file $hv_config_file"
                    fi
                fi
            fi
        fi

        # Success - using new config structure
        if [[ "$loaded_default" == "true" ]]; then
            if [[ "$loaded_hypervisor" == "true" ]]; then
                config_info "Configuration loaded successfully (modular)"
            else
                config_info "Configuration loaded (default only, no hypervisor-specific config)"
            fi
            return 0
        fi
    fi

    # Fallback to legacy rook_ceph.conf
    if [[ -f "$PROJECT_ROOT/rook_ceph.conf" ]]; then
        config_warn "Using legacy configuration file: rook_ceph.conf"
        config_warn "Consider migrating to new config structure in config/"
        config_warn "See: config/README.md for migration guide"
        source "$PROJECT_ROOT/rook_ceph.conf"
        used_legacy=true
        return 0
    fi

    # No configuration found
    config_error "No configuration file found!"
    config_error "Expected one of:"
    config_error "  - config/default.conf (new structure)"
    config_error "  - rook_ceph.conf (legacy)"
    config_error ""
    config_error "To create new configuration:"
    config_error "  cp config/examples/proxmox.conf config/proxmox.conf"
    config_error "  # Edit config/default.conf and config/proxmox.conf"
    return 1
}

###############################################################################
# Validation Functions
###############################################################################

validate_required_vars() {
    local missing_vars=()
    local required_vars=(
        "HYPERVISOR"
        "GATEWAY"
        "BASE_IP"
        "VM_PREFIX"
        "NODE_COUNT"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        config_error "Missing required configuration variables:"
        for var in "${missing_vars[@]}"; do
            config_error "  - $var"
        done
        return 1
    fi

    return 0
}

###############################################################################
# Execute if sourced
###############################################################################

# Only load config if this script is sourced (not executed)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    load_configuration
fi
