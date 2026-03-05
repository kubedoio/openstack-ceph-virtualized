# Project Refactoring Plan

## Current Issues

### 1. **Confusing File Organization**
- Too many scripts in root directory (12 shell scripts)
- Unclear naming: `1-rook-ceph.sh`, `2-os.sh` vs `deploy_rook_ceph.sh`, `deploy_openstack.sh`
- Setup scripts mixed with deployment scripts
- Simulation script is massive (51K) and in wrong location

### 2. **Configuration Complexity**
- Single monolithic config file (`rook_ceph.conf`) with 60+ lines
- Mixed concerns: hypervisor, network, Kubernetes, OpenStack, Ceph
- Hard to understand which settings apply to which hypervisor
- Hybrid mode settings scattered

### 3. **Unclear Execution Order**
- Users don't know which script to run first
- Numbered scripts (`1-`, `2-`) suggest order but also have descriptive names (`deploy_*`)
- No clear entry point for new users
- Setup vs deployment confusion

### 4. **Documentation Overload**
- 8 documentation files in `docs/` directory
- Some overlap and redundancy
- Hard to find the right guide for specific use case

## Proposed New Structure

```
openstack-ceph-virtualized/
├── config/
│   ├── default.conf                    # Main configuration with sensible defaults
│   ├── examples/
│   │   ├── proxmox.conf               # Proxmox-specific overrides
│   │   ├── cloudhypervisor.conf       # Cloud Hypervisor overrides
│   │   └── hybrid.conf                # Hybrid mode overrides
│   └── README.md                      # Configuration guide
│
├── bin/                                # Main executable scripts
│   ├── setup                          # Master setup script (interactive)
│   ├── deploy                         # Master deployment script
│   ├── create-vm                      # VM creation utility
│   └── destroy                        # Cleanup script
│
├── scripts/                           # Internal scripts (not directly called by users)
│   ├── setup/
│   │   ├── setup-proxmox.sh          # Proxmox setup (template creation)
│   │   ├── setup-cloudhypervisor.sh  # Cloud Hypervisor setup
│   │   └── setup-hybrid.sh           # Hybrid mode setup
│   ├── deploy/
│   │   ├── deploy-vms.sh             # VM deployment
│   │   ├── deploy-kubernetes.sh      # Kubernetes cluster
│   │   ├── deploy-rook-ceph.sh       # Rook-Ceph storage
│   │   └── deploy-openstack.sh       # OpenStack services
│   └── utils/
│       ├── validate-config.sh        # Configuration validation
│       ├── check-prerequisites.sh    # Prerequisites check
│       └── generate-inventory.sh     # Ansible inventory generation
│
├── lib/                               # Library functions (unchanged)
│   ├── hypervisor.sh
│   ├── hypervisors/
│   │   ├── proxmox.sh
│   │   ├── cloudhypervisor.sh
│   │   └── proxmox-cloudhypervisor.sh
│   └── common/
│       ├── network.sh
│       ├── storage.sh
│       └── cloudinit.sh
│
├── docs/                              # Consolidated documentation
│   ├── README.md                      # Documentation index
│   ├── getting-started.md            # Quick start (replaces multiple guides)
│   ├── hypervisors/
│   │   ├── proxmox.md
│   │   ├── cloudhypervisor.md
│   │   └── hybrid-mode.md
│   ├── architecture.md
│   ├── configuration.md
│   └── troubleshooting.md
│
├── tests/                             # Test scripts
│   ├── test-hypervisor-detection.sh
│   ├── test-vm-creation.sh
│   └── simulate-deployment.sh        # Moved from root
│
├── examples/                          # Example deployments
│   ├── basic-cluster/
│   └── production-ha/
│
├── README.md                          # Main project README
├── LICENSE
└── .gitignore
```

## Key Improvements

### 1. **Clear Entry Points**

**Before:**
```bash
# Confusing - which one to use?
./cloud-init-template.sh
./setup-cloud-hypervisor.sh
./setup-hybrid-mode.sh
./deploy_rook_ceph.sh
./1-rook-ceph.sh
```

**After:**
```bash
# Clear, single command with interactive wizard
./bin/setup

# Or specify mode directly
./bin/setup --hypervisor=proxmox
./bin/setup --hypervisor=cloudhypervisor
./bin/setup --hypervisor=hybrid

# Then deploy
./bin/deploy
```

### 2. **Simplified Configuration**

**Before:** One massive file
```bash
# rook_ceph.conf (60+ lines, all hypervisors mixed)
HYPERVISOR="auto"
CH_VM_DIR="/var/lib/cloud-hypervisor/vms"
HYBRID_BRIDGE_INTERNAL="vmbr1199"
TEMPLATE_ID=4444
...
```

**After:** Modular configs
```bash
# config/default.conf (common settings)
VM_PREFIX="os"
NODE_COUNT=6
NETWORK_INTERNAL="10.1.199.0/24"
NETWORK_GATEWAY="10.1.199.254"

# config/examples/proxmox.conf (Proxmox-specific)
HYPERVISOR="proxmox"
TEMPLATE_ID=4444
BRIDGE_INTERNAL="vmbr1199"
BRIDGE_EXTERNAL="vmbr2199"

# config/examples/hybrid.conf (Hybrid-specific)
HYPERVISOR="proxmox-cloudhypervisor"
CH_VM_DIR="/var/lib/cloud-hypervisor/vms"
HYBRID_BRIDGE_INTERNAL="vmbr1199"
VM_ID_START=5000
```

### 3. **Organized Script Structure**

**bin/** - User-facing commands (simple, documented)
- Master scripts with clear help text
- Interactive wizards for setup
- Validation before execution

**scripts/** - Internal implementation (complex logic)
- Hypervisor-specific setup
- Deployment steps broken down
- Utilities for validation and checks

**lib/** - Shared functions (no direct execution)
- Hypervisor abstraction
- Common utilities
- Imported by other scripts

### 4. **Better Documentation**

**Before:** 8 separate files, unclear which to read
- README.md
- docs/INSTALLATION_GUIDE.md
- docs/CLOUD_HYPERVISOR.md
- docs/HYBRID_MODE.md
- docs/HYPERVISOR_ABSTRACTION.md
- docs/ARCHITECTURE.md
- docs/CONFIGURATION.md
- docs/TROUBLESHOOTING.md

**After:** Clear hierarchy
```
README.md                        # Overview, quick start, links
docs/getting-started.md          # Comprehensive beginner guide
docs/hypervisors/
  ├── proxmox.md                # Proxmox-specific guide
  ├── cloudhypervisor.md        # Cloud Hypervisor guide
  └── hybrid-mode.md            # Hybrid mode guide
docs/architecture.md             # Technical details
docs/configuration.md            # Configuration reference
docs/troubleshooting.md          # Common issues
```

## Migration Strategy

### Phase 1: Configuration Refactoring (Low Risk)
1. Create `config/` directory
2. Split `rook_ceph.conf` into modular files
3. Create `config/examples/` with hypervisor-specific configs
4. Add config validation script
5. Update scripts to load configs from new location
6. **Keep old `rook_ceph.conf` as symlink for backward compatibility**

### Phase 2: Script Organization (Medium Risk)
1. Create `bin/`, `scripts/`, `tests/` directories
2. Create master `bin/setup` and `bin/deploy` scripts
3. Move existing scripts to `scripts/` subdirectories
4. Create wrapper scripts in `bin/` that call internal scripts
5. **Keep old scripts in root as symlinks to new locations**
6. Add deprecation warnings to old scripts

### Phase 3: Documentation Consolidation (Low Risk)
1. Create `docs/getting-started.md` (merge installation guides)
2. Reorganize hypervisor docs into `docs/hypervisors/`
3. Update README.md with new structure
4. Add navigation between docs
5. **Keep old docs with redirects to new locations**

### Phase 4: Testing & Cleanup (Final Step)
1. Test all workflows with new structure
2. Update CI/CD if applicable
3. Remove symlinks after deprecation period
4. Archive old files to `legacy/` directory
5. Final documentation pass

## Backward Compatibility

### During Transition
```bash
# Old way still works (via symlinks)
./deploy_rook_ceph.sh           # → bin/deploy --stage=rook-ceph

# New way recommended
./bin/deploy --stage=rook-ceph

# Old config still works
source rook_ceph.conf           # → config/default.conf + config/<hypervisor>.conf

# New config preferred
./bin/setup --config=config/examples/proxmox.conf
```

### Deprecation Timeline
- **Week 1-2**: Create new structure, keep old files as symlinks
- **Week 3-4**: Add deprecation warnings to old scripts
- **Week 5-6**: Update all documentation to use new structure
- **Week 7+**: Remove symlinks, archive old files

## Implementation Checklist

### Phase 1: Configuration
- [ ] Create `config/` directory structure
- [ ] Create `config/default.conf` with common settings
- [ ] Create `config/examples/proxmox.conf`
- [ ] Create `config/examples/cloudhypervisor.conf`
- [ ] Create `config/examples/hybrid.conf`
- [ ] Create `config/README.md` documentation
- [ ] Create `scripts/utils/validate-config.sh`
- [ ] Update all scripts to source new config files
- [ ] Create symlink: `rook_ceph.conf` → `config/default.conf`
- [ ] Test config loading in all scripts

### Phase 2: Script Organization
- [ ] Create `bin/` directory
- [ ] Create `scripts/setup/` directory
- [ ] Create `scripts/deploy/` directory
- [ ] Create `scripts/utils/` directory
- [ ] Create master `bin/setup` script (interactive wizard)
- [ ] Create master `bin/deploy` script (orchestrator)
- [ ] Create `bin/create-vm` (wrapper for VM creation)
- [ ] Move setup scripts to `scripts/setup/`
- [ ] Move deployment scripts to `scripts/deploy/`
- [ ] Create symlinks in root for old script names
- [ ] Add deprecation warnings to symlinked scripts
- [ ] Test all execution paths

### Phase 3: Documentation
- [ ] Create `docs/getting-started.md`
- [ ] Create `docs/hypervisors/` directory
- [ ] Move hypervisor docs to subdirectory
- [ ] Update README.md with new structure
- [ ] Create `docs/README.md` (documentation index)
- [ ] Add cross-references between docs
- [ ] Remove redundant content
- [ ] Create quick reference card

### Phase 4: Testing & Cleanup
- [ ] Create `tests/` directory
- [ ] Move `simulate-deployment.sh` to `tests/`
- [ ] Create integration tests
- [ ] Test Proxmox workflow end-to-end
- [ ] Test Cloud Hypervisor workflow end-to-end
- [ ] Test Hybrid mode workflow end-to-end
- [ ] Update CI/CD pipelines
- [ ] Remove symlinks
- [ ] Archive old files to `legacy/`
- [ ] Final documentation review

## Example: New User Experience

### Before Refactoring
```bash
# User is confused about what to run first
$ ls *.sh
1-rook-ceph.sh  2-os.sh  cloud-init-template.sh  create-k8s.sh
create-vm.sh  deploy_openstack.sh  deploy_rook_ceph.sh
setup-cloud-hypervisor.sh  setup-hybrid-mode.sh

# User reads multiple guides to figure out order
$ cat docs/INSTALLATION_GUIDE.md
$ cat docs/CLOUD_HYPERVISOR.md
$ cat docs/HYBRID_MODE.md

# User manually runs multiple commands
$ ./setup-hybrid-mode.sh
$ vi rook_ceph.conf  # Edit complex config
$ ./create-vm.sh 4444 5001 os1.local 10.1.199.141/24 10.1.199.254
$ ./deploy_rook_ceph.sh
```

### After Refactoring
```bash
# User runs single command
$ ./bin/setup

# Interactive wizard guides through setup
Welcome to OpenStack-Ceph Infrastructure Setup
==============================================

1. Select hypervisor:
   [1] Proxmox VE
   [2] Cloud Hypervisor (bare metal)
   [3] Hybrid (Cloud Hypervisor on Proxmox)

   Choice: 3

2. Verify Proxmox bridges:
   ✓ vmbr1199 found (10.1.199.254/24)
   ✓ vmbr2199 found (10.2.199.254/24)

3. Install Cloud Hypervisor? [Y/n]: y
   ✓ Downloaded Cloud Hypervisor v39.0
   ✓ Installed to /usr/local/bin/cloud-hypervisor

4. Download Ubuntu template? [Y/n]: y
   ✓ Downloaded ubuntu-24.04-server-cloudimg-amd64.img
   ✓ Converted to raw format

Configuration saved to: config/hybrid.conf

Setup complete! Next steps:
  1. Add SSH keys to 'pub_keys' file
  2. Run './bin/deploy' to create VMs and deploy cluster

# User runs single deploy command
$ ./bin/deploy

Deployment Plan
===============
Stage 1: Create 7 VMs (os0-os6)
Stage 2: Deploy Kubernetes cluster
Stage 3: Deploy Rook-Ceph storage
Stage 4: Deploy OpenStack services

Proceed? [Y/n]: y

[Stage 1] Creating VMs...
  ✓ os0.local (10.1.199.140) - Jump host
  ✓ os1.local (10.1.199.141) - K8s node 1
  ...

[Stage 2] Deploying Kubernetes...
  ✓ Kubespray inventory generated
  ✓ Running ansible-playbook...

...
```

## Benefits Summary

### For New Users
- **Single entry point**: `./bin/setup` guides through everything
- **Clear documentation**: One getting-started guide instead of 8 files
- **Validation**: Scripts check prerequisites and configs before running
- **Better errors**: Clear messages about what went wrong and how to fix

### For Experienced Users
- **Modular configs**: Only edit what's relevant to your hypervisor
- **Scriptable**: Can bypass wizard with `./bin/setup --config=...`
- **Organized**: Easy to find and modify specific functionality
- **Testable**: Unit tests for each component

### For Developers
- **Clear structure**: Know where to add new features
- **Separation of concerns**: Setup vs deploy vs utilities
- **Backward compatible**: Changes don't break existing workflows
- **Maintainable**: Less code duplication, better organization

## Risk Assessment

### Low Risk Changes
✅ Configuration splitting (keep old file as fallback)
✅ Documentation reorganization (keep old docs)
✅ Adding new wrapper scripts (don't touch old scripts)

### Medium Risk Changes
⚠️ Moving scripts to subdirectories (use symlinks)
⚠️ Changing config loading logic (need thorough testing)

### High Risk Changes
🔴 Removing old scripts (only after deprecation period)
🔴 Breaking config file format (requires migration script)

**Recommended Approach**: Execute all phases but keep backward compatibility via symlinks and fallbacks. Remove legacy only after 2-3 months of stable usage.

## Timeline

- **Phase 1 (Configuration)**: 2-3 days
- **Phase 2 (Scripts)**: 3-4 days
- **Phase 3 (Documentation)**: 2-3 days
- **Phase 4 (Testing)**: 2-3 days

**Total**: ~10-14 days of work

**Incremental approach**: Can merge after each phase, users benefit immediately

## Decision Points

Before starting implementation, confirm:

1. **Backward compatibility requirement?**
   - Keep old scripts as symlinks? (Recommended: Yes)
   - Keep old config format working? (Recommended: Yes)
   - Deprecation timeline? (Recommended: 2-3 months)

2. **Interactive setup wizard?**
   - Add interactive mode to `bin/setup`? (Recommended: Yes)
   - Support non-interactive mode? (Recommended: Yes, via flags)

3. **Documentation approach?**
   - One getting-started guide? (Recommended: Yes)
   - Keep detailed hypervisor-specific guides? (Recommended: Yes, in subdirs)

4. **Testing requirements?**
   - Need automated tests before merging? (Recommended: Yes, basic tests)
   - Integration tests for all hypervisors? (Recommended: Yes, via simulation)

## Next Steps

1. **Review this plan** - Get approval on structure and approach
2. **Start with Phase 1** - Config refactoring (lowest risk, immediate benefit)
3. **Test thoroughly** - Ensure nothing breaks
4. **Merge incrementally** - Don't wait for all phases to complete
5. **Iterate based on feedback** - Adjust plan as needed

---

**Recommendation**: Start with Phase 1 (configuration refactoring) as it's the lowest risk and provides immediate clarity for users. Then proceed to Phase 2 if Phase 1 is successful.
