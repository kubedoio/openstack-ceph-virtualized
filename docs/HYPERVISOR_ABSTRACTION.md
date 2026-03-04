# Hypervisor Abstraction Layer - Developer Guide

This document explains the hypervisor abstraction architecture for developers who want to understand, extend, or maintain the multi-hypervisor support.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Design Principles](#design-principles)
- [Directory Structure](#directory-structure)
- [Core Components](#core-components)
- [Adding a New Hypervisor](#adding-a-new-hypervisor)
- [API Reference](#api-reference)
- [Testing](#testing)

## Architecture Overview

The abstraction layer provides a **single unified API** that works across different hypervisors. Scripts use this API instead of calling hypervisor-specific commands directly.

### Layer Stack

```
┌──────────────────────────────────────────────────────────┐
│  User Scripts (deploy_rook_ceph.sh, create-vm.sh)       │
└────────────────────┬─────────────────────────────────────┘
                     │ Uses: hv_create_vm(), hv_start_vm(), etc.
        ┌────────────┴────────────┐
        │  lib/hypervisor.sh       │  (Abstraction API)
        │  - Auto-detection         │
        │  - Function routing       │
        │  - Common interface       │
        └────────┬─────────┬────────┘
                 │         │
    ┌────────────┴──┐   ┌──┴─────────────┐
    │  proxmox.sh   │   │cloudhypervisor.sh│ (Backend Implementations)
    │  - qm commands│   │  - ch-remote    │
    └───────┬───────┘   └────────┬────────┘
            │                    │
    ┌───────┴────────┐   ┌───────┴────────┐
    │  Proxmox VE    │   │Cloud Hypervisor│ (Actual Hypervisors)
    │  (qm, pct)     │   │ (REST API)     │
    └────────────────┘   └────────────────┘
```

### Flow Example: Creating a VM

```bash
# User calls abstraction API
hv_create_vm 4141 "os1" 4 8192

# lib/hypervisor.sh routes to detected hypervisor
if [[ $HV_TYPE == "proxmox" ]]; then
    proxmox_create_vm 4141 "os1" 4 8192
elif [[ $HV_TYPE == "cloudhypervisor" ]]; then
    cloudhypervisor_create_vm 4141 "os1" 4 8192
fi

# Backend implementation executes hypervisor-specific commands
# Proxmox: qm create 4141 --name os1 --cores 4 --memory 8192
# Cloud Hypervisor: Creates JSON config + directory structure
```

## Design Principles

### 1. **Single Source of Truth**

All hypervisor operations go through `lib/hypervisor.sh`. No script should call `qm` or `cloud-hypervisor` directly.

**Bad:**
```bash
qm start 4141
```

**Good:**
```bash
source lib/hypervisor.sh
hv_init
hv_start_vm 4141
```

### 2. **Transparent Detection**

The system automatically detects the available hypervisor. Users don't need to configure anything unless they want to override.

```bash
# Auto-detect (default)
HYPERVISOR=auto ./deploy_rook_ceph.sh

# Explicit override
HYPERVISOR=cloudhypervisor ./deploy_rook_ceph.sh
```

### 3. **Feature Parity**

Both implementations support identical operations. If a feature works on Proxmox, it should work on Cloud Hypervisor (and vice versa).

### 4. **Zero Breaking Changes**

Existing Proxmox scripts work unchanged. The abstraction is **additive only**.

### 5. **Fail Fast**

If an operation isn't supported or fails, return immediately with a clear error. Don't attempt fallbacks that could cause data loss.

## Directory Structure

```
lib/
├── hypervisor.sh              # Main abstraction layer (300 lines)
│                              # - Detection logic
│                              # - API definitions
│                              # - Function routing
│
├── hypervisors/               # Backend implementations
│   ├── proxmox.sh            # Proxmox VE backend (400 lines)
│   │                         # - qm command wrappers
│   └── cloudhypervisor.sh    # Cloud Hypervisor backend (800 lines)
│                             # - VM lifecycle management
│                             # - API socket communication
│
└── common/                    # Shared utilities
    ├── cloudinit.sh          # Cloud-init ISO generation (200 lines)
    │                         # - NoCloud format
    │                         # - user-data / meta-data
    ├── network.sh            # Network management (200 lines)
    │                         # - Bridge creation
    │                         # - TAP device management
    └── storage.sh            # Storage utilities (300 lines)
                              # - Disk creation / cloning
                              # - Format conversion (qcow2 ↔ raw)
```

## Core Components

### lib/hypervisor.sh

**Purpose:** Main abstraction interface

**Key Functions:**
- `detect_hypervisor()` - Auto-detect Proxmox or Cloud Hypervisor
- `hv_init()` - Initialize hypervisor backend
- `hv_*()` - Unified API functions (route to backend)

**Initialization:**
```bash
source lib/hypervisor.sh

# Initialize (detects hypervisor, loads backend)
hv_init

# Check which hypervisor is active
echo "Using: $(hv_get_type)"

# Check specific hypervisor
if hv_is_proxmox; then
    echo "Running on Proxmox VE"
fi
```

### lib/hypervisors/proxmox.sh

**Purpose:** Proxmox VE backend implementation

**Pattern:** Thin wrappers around `qm` commands

**Example:**
```bash
proxmox_start_vm() {
    local vm_id="$1"

    if ! proxmox_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    qm start "$vm_id"
}
```

### lib/hypervisors/cloudhypervisor.sh

**Purpose:** Cloud Hypervisor backend implementation

**Pattern:** Manages VM config files + process lifecycle

**Example:**
```bash
cloudhypervisor_start_vm() {
    local vm_id="$1"
    local config_file=$(_ch_vm_config "$vm_id")

    # Parse config to build command
    local cpus=$(jq -r '.cpus.boot_vcpus' "$config_file")
    local memory_mb=$(($(jq -r '.memory.size' "$config_file") / 1024 / 1024))

    # Launch cloud-hypervisor process
    cloud-hypervisor \
        --api-socket "$(_ch_vm_socket "$vm_id")" \
        --cpus "boot=${cpus}" \
        --memory "size=${memory_mb}M" \
        ...
}
```

### lib/common/*.sh

**Purpose:** Shared utilities used by backends

**Independent:** Can be used standalone without abstraction layer

**Example:**
```bash
source lib/common/network.sh

# Create bridge
create_bridge chbr1199 10.1.199.254/24

# Create TAP device attached to bridge
create_tap_device tap-vm0-0 chbr1199
```

## Adding a New Hypervisor

To add support for a new hypervisor (e.g., QEMU/KVM, Firecracker):

### Step 1: Create Backend Implementation

Create `lib/hypervisors/yourname.sh`:

```bash
#!/usr/bin/env bash

# Initialize
yourname_init() {
    # Check if hypervisor is available
    if ! command -v yourtool >/dev/null 2>&1; then
        echo "ERROR: yourtool not found" >&2
        return 1
    fi
    return 0
}

# Implement all required functions
yourname_create_vm() {
    local vm_id="$1"
    local name="$2"
    local cores="$3"
    local memory_mb="$4"

    # Your implementation here
    echo "Creating VM $vm_id with yourtool..."
}

yourname_start_vm() {
    local vm_id="$1"
    # Your implementation here
}

# ... implement all other functions

# Export functions
export -f yourname_init
export -f yourname_create_vm
export -f yourname_start_vm
# ... export all functions
```

### Step 2: Update Detection Logic

Edit `lib/hypervisor.sh`:

```bash
detect_hypervisor() {
    local config_hv="${HYPERVISOR:-auto}"

    if [[ "$config_hv" != "auto" ]]; then
        case "$config_hv" in
            proxmox|cloudhypervisor|yourname)  # Add here
                echo "$config_hv"
                return 0
                ;;
            *)
                echo "ERROR: Unknown hypervisor type: $config_hv" >&2
                return 1
                ;;
        esac
    fi

    # Auto-detection
    if command -v qm >/dev/null 2>&1; then
        echo "proxmox"
        return 0
    fi

    if command -v cloud-hypervisor >/dev/null 2>&1; then
        echo "cloudhypervisor"
        return 0
    fi

    # Add your detection logic
    if command -v yourtool >/dev/null 2>&1; then
        echo "yourname"
        return 0
    fi

    echo "ERROR: No supported hypervisor detected" >&2
    return 1
}
```

### Step 3: Test Implementation

```bash
# Force your hypervisor
export HYPERVISOR=yourname

# Test initialization
source lib/hypervisor.sh
hv_init

# Test VM creation
hv_create_vm 9999 "test" 2 2048
hv_start_vm 9999
hv_vm_status 9999
hv_stop_vm 9999
hv_destroy_vm 9999
```

### Step 4: Document

Create `docs/YOURNAME.md` with:
- Installation instructions
- Configuration guide
- Limitations vs other hypervisors
- Troubleshooting

## API Reference

### VM Lifecycle

#### `hv_create_vm <vm_id> <name> <cores> <memory_mb>`
Create a new VM.

**Example:**
```bash
hv_create_vm 4141 "os1" 4 8192
```

#### `hv_start_vm <vm_id>`
Start a VM.

#### `hv_stop_vm <vm_id>`
Stop a VM (forcefully).

#### `hv_shutdown_vm <vm_id>`
Shutdown a VM gracefully.

#### `hv_destroy_vm <vm_id>`
Destroy/delete a VM and all its resources.

#### `hv_vm_exists <vm_id>`
Check if VM exists (returns 0 if yes, 1 if no).

#### `hv_vm_status <vm_id>`
Get VM status (returns: "running", "stopped", "unknown").

#### `hv_wait_vm_running <vm_id> [timeout_seconds]`
Wait for VM to reach running state.

### VM Configuration

#### `hv_set_cores <vm_id> <cores>`
Set CPU cores.

#### `hv_set_memory <vm_id> <memory_mb>`
Set memory in MB.

#### `hv_clone_template <vm_id> <template_id>`
Clone VM from template.

### Network

#### `hv_add_network <vm_id> <bridge> [mac] [model]`
Add network interface to VM.

#### `hv_set_network <vm_id> <interface_index> <bridge> [mac] [model]`
Configure specific network interface.

### Storage

#### `hv_add_disk <vm_id> <disk_spec> <size_gb> [disk_index]`
Add disk to VM.

**Proxmox:** `disk_spec` = storage name (e.g., "local")
**Cloud Hypervisor:** `disk_spec` = disk size, creates raw file

#### `hv_resize_disk <vm_id> <disk_index> <size_increase_gb>`
Resize disk (increase only).

#### `hv_import_disk <vm_id> <disk_path> <storage> [disk_index]`
Import external disk to VM.

### Cloud-Init

#### `hv_set_cloudinit <vm_id> <cloudinit_iso_path>`
Attach cloud-init ISO to VM.

#### `hv_set_cloudinit_user <vm_id> <username> <ssh_keys_file>`
Configure cloud-init user and SSH keys.

#### `hv_set_cloudinit_network <vm_id> <ip_cidr> <gateway>`
Configure cloud-init network settings.

### Templates

#### `hv_create_template <vm_id>`
Convert VM to template.

#### `hv_create_template_from_image <template_id> <image_url>`
Create template from cloud image.

### Utility

#### `hv_get_type`
Get current hypervisor type ("proxmox" or "cloudhypervisor").

#### `hv_is_proxmox`
Returns 0 if using Proxmox.

#### `hv_is_cloudhypervisor`
Returns 0 if using Cloud Hypervisor.

#### `hv_info`
Print hypervisor information.

## Testing

### Unit Tests

Test individual backend functions:

```bash
# Test Proxmox backend
source lib/hypervisors/proxmox.sh
proxmox_init
proxmox_create_vm 9999 "test" 2 2048
proxmox_start_vm 9999
proxmox_vm_status 9999
proxmox_destroy_vm 9999

# Test Cloud Hypervisor backend
source lib/hypervisors/cloudhypervisor.sh
cloudhypervisor_init
cloudhypervisor_create_vm 9999 "test" 2 2048
# ...
```

### Integration Tests

Test via abstraction layer:

```bash
# Test abstraction with Proxmox
export HYPERVISOR=proxmox
source lib/hypervisor.sh
hv_init
./create-vm.sh 4444 9999 test.local 10.1.199.199/24 10.1.199.254

# Test abstraction with Cloud Hypervisor
export HYPERVISOR=cloudhypervisor
source lib/hypervisor.sh
hv_init
./create-vm.sh 4444 9998 test2.local 10.1.199.198/24 10.1.199.254
```

### End-to-End Tests

Full deployment tests:

```bash
# Test on Proxmox
export HYPERVISOR=proxmox
./deploy_rook_ceph.sh

# Verify Kubernetes cluster
kubectl get nodes
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s

# Test on Cloud Hypervisor
export HYPERVISOR=cloudhypervisor
./deploy_rook_ceph.sh

# Same verification
kubectl get nodes
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
```

### Compatibility Matrix

| Feature | Proxmox | Cloud Hypervisor | Notes |
|---------|---------|------------------|-------|
| VM create | ✅ | ✅ | Full parity |
| VM start/stop | ✅ | ✅ | |
| CPU/Memory config | ✅ | ✅ | |
| Multi-NIC | ✅ | ✅ | |
| Multi-disk | ✅ | ✅ | |
| Cloud-init | ✅ (built-in) | ✅ (NoCloud) | Different methods |
| Live migration | ✅ | ❌ | Proxmox only |
| Snapshots | ✅ (GUI) | ⚠️ (manual) | qemu-img snapshot |
| Console access | ✅ (VNC) | ✅ (serial) | Different protocols |

## Common Patterns

### Error Handling

Always check for errors and return non-zero:

```bash
my_function() {
    local vm_id="$1"

    # Validate input
    if [[ -z "$vm_id" ]]; then
        echo "ERROR: VM ID required" >&2
        return 1
    fi

    # Check prerequisites
    if ! my_vm_exists "$vm_id"; then
        echo "ERROR: VM $vm_id does not exist" >&2
        return 1
    fi

    # Perform operation
    my_tool do_something "$vm_id" || {
        echo "ERROR: Operation failed for VM $vm_id" >&2
        return 1
    }

    return 0
}
```

### Logging

Use INFO/WARN/ERROR prefixes:

```bash
echo "INFO: Starting VM $vm_id" >&2
echo "WARN: No cloud-init ISO found, using defaults" >&2
echo "ERROR: Failed to create VM $vm_id" >&2
```

### Configuration Parsing

Use jq for JSON config files:

```bash
local cpus=$(jq -r '.cpus.boot_vcpus' "$config_file")
local memory=$(jq -r '.memory.size' "$config_file")
```

### Idempotency

Check state before operations:

```bash
if my_vm_exists "$vm_id"; then
    echo "INFO: VM $vm_id already exists, skipping creation"
    return 0
fi

# Proceed with creation...
```

## Debugging

### Enable Debug Mode

```bash
# Set bash debug mode
set -x

# Run with verbose output
export DEBUG=1
./deploy_rook_ceph.sh
```

### Check Loaded Hypervisor

```bash
source lib/hypervisor.sh
hv_init
hv_info
```

### Trace Function Calls

```bash
# Add to script
declare -F  # List all functions
type hv_create_vm  # Show function definition
```

## Contributing

### Code Style

- Use `snake_case` for functions and variables
- Prefix backend functions with hypervisor name: `proxmox_`, `cloudhypervisor_`
- Keep functions focused (one task per function)
- Document complex logic with comments

### Pull Request Checklist

- [ ] Test on both Proxmox and Cloud Hypervisor
- [ ] Update API documentation
- [ ] Add error handling
- [ ] Update relevant docs/*.md files
- [ ] No breaking changes to existing Proxmox deployments

## Future Enhancements

Potential improvements:

1. **Additional Hypervisors**
   - QEMU/KVM (libvirt)
   - Firecracker
   - AWS (EC2)
   - Azure (VMs)

2. **Enhanced Features**
   - VM snapshots (unified API)
   - Live migration abstraction
   - Resource monitoring
   - Automated testing framework

3. **Performance**
   - Parallel VM creation
   - Optimized disk cloning
   - Network performance tuning

4. **Observability**
   - Structured logging (JSON)
   - Metrics collection
   - Health checks

## References

- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Cloud Hypervisor API](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/vmm/src/api/openapi/cloud-hypervisor.yaml)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Linux Bridge Configuration](https://wiki.linuxfoundation.org/networking/bridge)
