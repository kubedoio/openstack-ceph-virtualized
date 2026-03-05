#!/usr/bin/env bash
###############################################################################
# scripts/utils/validate-config.sh - Configuration Validation
#
# Validates configuration settings and provides helpful error messages.
#
# Usage:
#   ./scripts/utils/validate-config.sh
#   # Or source and call validate_config function
#
# Exit codes:
#   0 - Configuration is valid
#   1 - Configuration has errors
###############################################################################

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"

# Color output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

error_count=0
warn_count=0

validation_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    ((error_count++))
}

validation_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    ((warn_count++))
}

validation_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

###############################################################################
# Validation Functions
###############################################################################

validate_required_variables() {
    echo "Validating required variables..."

    local required_vars=(
        "HYPERVISOR:Hypervisor type"
        "GATEWAY:Network gateway"
        "BASE_IP:Base IP address"
        "VM_PREFIX:VM name prefix"
        "NODE_COUNT:Number of nodes"
        "PUB_KEY_FILE:SSH public key file"
    )

    for var_desc in "${required_vars[@]}"; do
        IFS=':' read -r var desc <<< "$var_desc"
        if [[ -z "${!var:-}" ]]; then
            validation_error "$desc ($var) is not set"
        else
            validation_ok "$desc: ${!var}"
        fi
    done
}

validate_hypervisor() {
    echo ""
    echo "Validating hypervisor configuration..."

    case "${HYPERVISOR}" in
        auto)
            validation_ok "Hypervisor: auto-detect"
            ;;
        proxmox)
            validation_ok "Hypervisor: Proxmox VE"
            if [[ -z "${TEMPLATE_ID:-}" ]]; then
                validation_error "TEMPLATE_ID not set (required for Proxmox)"
            else
                validation_ok "Template ID: $TEMPLATE_ID"
            fi
            if [[ -z "${BRIDGE_INTERNAL:-}" ]]; then
                validation_warn "BRIDGE_INTERNAL not set (defaulting to vmbr1199)"
            fi
            ;;
        cloudhypervisor)
            validation_ok "Hypervisor: Cloud Hypervisor"
            if [[ -z "${CH_VM_DIR:-}" ]]; then
                validation_error "CH_VM_DIR not set (required for Cloud Hypervisor)"
            else
                validation_ok "VM directory: $CH_VM_DIR"
            fi
            if [[ -z "${CH_IMAGE_DIR:-}" ]]; then
                validation_error "CH_IMAGE_DIR not set (required for Cloud Hypervisor)"
            else
                validation_ok "Image directory: $CH_IMAGE_DIR"
            fi
            ;;
        proxmox-cloudhypervisor|hybrid|pve-ch)
            validation_ok "Hypervisor: Hybrid Mode"
            if [[ -z "${HYBRID_BRIDGE_INTERNAL:-}" ]]; then
                validation_error "HYBRID_BRIDGE_INTERNAL not set (required for hybrid mode)"
            else
                validation_ok "Internal bridge: $HYBRID_BRIDGE_INTERNAL"
            fi
            if [[ -z "${HYBRID_BRIDGE_EXTERNAL:-}" ]]; then
                validation_error "HYBRID_BRIDGE_EXTERNAL not set (required for hybrid mode)"
            else
                validation_ok "External bridge: $HYBRID_BRIDGE_EXTERNAL"
            fi
            if [[ -z "${CH_VM_DIR:-}" ]]; then
                validation_error "CH_VM_DIR not set (required for hybrid mode)"
            fi
            ;;
        *)
            validation_error "Unknown hypervisor type: $HYPERVISOR"
            validation_error "Valid values: auto, proxmox, cloudhypervisor, proxmox-cloudhypervisor"
            ;;
    esac
}

validate_network() {
    echo ""
    echo "Validating network configuration..."

    # Validate IP format
    if [[ ! "$BASE_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        validation_error "BASE_IP format invalid: $BASE_IP (expected: X.X.X)"
    else
        validation_ok "Base IP: $BASE_IP"
    fi

    if [[ ! "$GATEWAY" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        validation_error "GATEWAY format invalid: $GATEWAY (expected: X.X.X.X)"
    else
        validation_ok "Gateway: $GATEWAY"
    fi

    # Validate IP suffix is numeric
    if [[ ! "$START_IP_SUFFIX" =~ ^[0-9]+$ ]]; then
        validation_error "START_IP_SUFFIX must be numeric: $START_IP_SUFFIX"
    elif [[ "$START_IP_SUFFIX" -lt 1 || "$START_IP_SUFFIX" -gt 254 ]]; then
        validation_error "START_IP_SUFFIX must be between 1-254: $START_IP_SUFFIX"
    else
        validation_ok "Starting IP: ${BASE_IP}.${START_IP_SUFFIX}"
    fi
}

validate_vm_configuration() {
    echo ""
    echo "Validating VM configuration..."

    # Validate node count
    if [[ ! "$NODE_COUNT" =~ ^[0-9]+$ ]]; then
        validation_error "NODE_COUNT must be numeric: $NODE_COUNT"
    elif [[ "$NODE_COUNT" -lt 1 ]]; then
        validation_error "NODE_COUNT must be at least 1: $NODE_COUNT"
    elif [[ "$NODE_COUNT" -gt 50 ]]; then
        validation_warn "NODE_COUNT is very large: $NODE_COUNT (are you sure?)"
    else
        validation_ok "Node count: $NODE_COUNT"
    fi

    # Validate VM prefix
    if [[ -z "$VM_PREFIX" ]]; then
        validation_error "VM_PREFIX cannot be empty"
    elif [[ ! "$VM_PREFIX" =~ ^[a-z][a-z0-9-]*$ ]]; then
        validation_error "VM_PREFIX must start with lowercase letter: $VM_PREFIX"
    else
        validation_ok "VM prefix: $VM_PREFIX"
        validation_ok "VM names: ${VM_PREFIX}0, ${VM_PREFIX}1, ..., ${VM_PREFIX}${NODE_COUNT}"
    fi

    # Validate resources
    if [[ ! "${DEFAULT_CORES:-4}" =~ ^[0-9]+$ ]]; then
        validation_error "DEFAULT_CORES must be numeric: ${DEFAULT_CORES}"
    elif [[ "${DEFAULT_CORES:-4}" -lt 1 ]]; then
        validation_error "DEFAULT_CORES must be at least 1"
    else
        validation_ok "Default cores: ${DEFAULT_CORES:-4}"
    fi

    if [[ ! "${DEFAULT_MEMORY_MB:-8192}" =~ ^[0-9]+$ ]]; then
        validation_error "DEFAULT_MEMORY_MB must be numeric: ${DEFAULT_MEMORY_MB}"
    elif [[ "${DEFAULT_MEMORY_MB:-8192}" -lt 2048 ]]; then
        validation_error "DEFAULT_MEMORY_MB must be at least 2048 (2GB)"
    else
        validation_ok "Default memory: ${DEFAULT_MEMORY_MB:-8192}MB"
    fi
}

validate_ssh_keys() {
    echo ""
    echo "Validating SSH configuration..."

    if [[ ! -f "$PROJECT_ROOT/$PUB_KEY_FILE" ]]; then
        validation_error "SSH public key file not found: $PUB_KEY_FILE"
        validation_error "Create it with: cat ~/.ssh/id_rsa.pub > $PUB_KEY_FILE"
    else
        local key_count=$(wc -l < "$PROJECT_ROOT/$PUB_KEY_FILE" | tr -d ' ')
        if [[ "$key_count" -eq 0 ]]; then
            validation_error "SSH public key file is empty: $PUB_KEY_FILE"
        else
            validation_ok "SSH keys found: $key_count key(s) in $PUB_KEY_FILE"
        fi
    fi
}

validate_directories() {
    echo ""
    echo "Validating directories..."

    # Check for required directories based on hypervisor
    case "${HYPERVISOR}" in
        cloudhypervisor|proxmox-cloudhypervisor|hybrid|pve-ch)
            if [[ -n "${CH_VM_DIR:-}" ]]; then
                if [[ ! -d "$CH_VM_DIR" ]]; then
                    validation_warn "VM directory does not exist: $CH_VM_DIR"
                    validation_warn "It will be created during setup"
                else
                    validation_ok "VM directory exists: $CH_VM_DIR"
                fi
            fi

            if [[ -n "${CH_IMAGE_DIR:-}" ]]; then
                if [[ ! -d "$CH_IMAGE_DIR" ]]; then
                    validation_warn "Image directory does not exist: $CH_IMAGE_DIR"
                    validation_warn "It will be created during setup"
                else
                    validation_ok "Image directory exists: $CH_IMAGE_DIR"
                fi
            fi
            ;;
    esac

    # Check for Kubespray directory
    if [[ -n "${KUBESPRAY_DIR:-}" ]]; then
        if [[ ! -d "$PROJECT_ROOT/$KUBESPRAY_DIR" ]]; then
            validation_warn "Kubespray directory not found: $KUBESPRAY_DIR"
            validation_warn "Clone it with: git clone https://github.com/kubernetes-sigs/kubespray"
        else
            validation_ok "Kubespray directory found: $KUBESPRAY_DIR"
        fi
    fi

    # Check for Kolla directory
    if [[ -n "${KOLLA_DIR:-}" ]]; then
        if [[ ! -d "$PROJECT_ROOT/$KOLLA_DIR" ]]; then
            validation_warn "Kolla directory not found: $KOLLA_DIR"
            validation_warn "Clone it with: git clone https://github.com/openstack/kolla-ansible"
        else
            validation_ok "Kolla directory found: $KOLLA_DIR"
        fi
    fi
}

validate_openstack_nodes() {
    echo ""
    echo "Validating OpenStack configuration..."

    if [[ -z "${OPENSTACK_NODE_LIST:-}" ]]; then
        validation_warn "OPENSTACK_NODE_LIST is empty (no OpenStack nodes)"
    else
        local node_count=${#OPENSTACK_NODE_LIST[@]}
        if [[ "$node_count" -eq 0 ]]; then
            validation_warn "OPENSTACK_NODE_LIST is empty (no OpenStack nodes)"
        else
            validation_ok "OpenStack nodes: $node_count"
            for node_entry in "${OPENSTACK_NODE_LIST[@]}"; do
                IFS=':' read -r node_name node_ip <<< "$node_entry"
                if [[ -z "$node_name" || -z "$node_ip" ]]; then
                    validation_error "Invalid OpenStack node entry: $node_entry (expected name:ip)"
                else
                    validation_ok "  - $node_name: $node_ip"
                fi
            done
        fi
    fi
}

###############################################################################
# Main Validation
###############################################################################

main() {
    echo "=========================================="
    echo "Configuration Validation"
    echo "=========================================="
    echo ""

    validate_required_variables
    validate_hypervisor
    validate_network
    validate_vm_configuration
    validate_ssh_keys
    validate_directories
    validate_openstack_nodes

    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="

    if [[ $error_count -eq 0 && $warn_count -eq 0 ]]; then
        echo -e "${GREEN}✓ Configuration is valid!${NC}"
        return 0
    elif [[ $error_count -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Configuration is valid with $warn_count warning(s)${NC}"
        return 0
    else
        echo -e "${RED}✗ Configuration has $error_count error(s) and $warn_count warning(s)${NC}"
        echo ""
        echo "Please fix the errors before proceeding."
        return 1
    fi
}

# Run validation if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
