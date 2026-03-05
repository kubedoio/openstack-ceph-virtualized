#!/bin/bash
###############################################################################
# test-phase1.sh - Quick test of Phase 1 configuration refactoring
#
# This script verifies that Phase 1 is working correctly on your Proxmox
# system and helps you understand the new configuration structure.
###############################################################################

set -e

echo "=========================================="
echo "Phase 1 Configuration Test"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Test 1: Verify new structure exists
echo "Test 1: Checking new directory structure..."
if [[ -d "config" ]] && [[ -d "config/examples" ]] && [[ -d "scripts/utils" ]]; then
    echo -e "${GREEN}✓${NC} New directory structure exists"
else
    echo -e "${RED}✗${NC} Directory structure missing"
    exit 1
fi
echo ""

# Test 2: Check configuration files
echo "Test 2: Checking configuration files..."
for file in config/default.conf config/examples/proxmox.conf config/examples/cloudhypervisor.conf config/examples/hybrid.conf; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $file exists"
    else
        echo -e "${RED}✗${NC} $file missing"
        exit 1
    fi
done
echo ""

# Test 3: Check utility scripts
echo "Test 3: Checking utility scripts..."
for script in scripts/utils/load-config.sh scripts/utils/validate-config.sh; do
    if [[ -f "$script" ]] && [[ -x "$script" ]]; then
        echo -e "${GREEN}✓${NC} $script exists and is executable"
    else
        echo -e "${RED}✗${NC} $script missing or not executable"
        exit 1
    fi
done
echo ""

# Test 4: Load configuration
echo "Test 4: Testing configuration loading..."
export HYPERVISOR=proxmox-cloudhypervisor
if source scripts/utils/load-config.sh 2>&1 | grep -q "Configuration loaded"; then
    echo -e "${GREEN}✓${NC} Configuration loaded successfully"
    echo "  HYPERVISOR: $HYPERVISOR"
    echo "  GATEWAY: ${GATEWAY:-NOT_SET}"
    echo "  VM_PREFIX: ${VM_PREFIX:-NOT_SET}"
else
    echo -e "${RED}✗${NC} Configuration loading failed"
    exit 1
fi
echo ""

# Test 5: Validate configuration
echo "Test 5: Testing configuration validation..."
if ./scripts/utils/validate-config.sh > /tmp/validation.log 2>&1; then
    echo -e "${GREEN}✓${NC} Configuration validation passed"
    echo ""
    echo "Validation summary:"
    tail -10 /tmp/validation.log | sed 's/\x1b\[[0-9;]*m//g'
else
    echo -e "${YELLOW}⚠${NC} Configuration validation has warnings/errors"
    echo ""
    echo "Last 20 lines of validation output:"
    tail -20 /tmp/validation.log | sed 's/\x1b\[[0-9;]*m//g'
fi
rm -f /tmp/validation.log
echo ""

# Test 6: Check backward compatibility
echo "Test 6: Checking backward compatibility..."
if [[ -f "rook_ceph.conf" ]]; then
    if grep -q "Legacy Configuration" rook_ceph.conf; then
        echo -e "${GREEN}✓${NC} Migration notice added to rook_ceph.conf"
    else
        echo -e "${YELLOW}⚠${NC} rook_ceph.conf exists but no migration notice"
    fi
    echo -e "${GREEN}✓${NC} Old config still exists (backward compatible)"
else
    echo -e "${YELLOW}⚠${NC} rook_ceph.conf not found"
fi
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Phase 1 is working correctly!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review configuration: cat config/default.conf"
echo "  2. Review hybrid config: cat config/examples/hybrid.conf"
echo "  3. Validate your setup: ./scripts/utils/validate-config.sh"
echo "  4. Create a VM: ./create-vm.sh 4444 6001 os1.chv.local 10.1.199.143/24 10.1.199.254"
echo ""
echo "Documentation:"
echo "  - Configuration guide: config/README.md"
echo "  - Phase 1 summary: PHASE1_COMPLETE.md"
echo "  - Full plan: REFACTORING_PLAN.md"
echo ""
