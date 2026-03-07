#!/bin/bash
# ==============================================================
# MASTER DEPLOY SCRIPT
# One-click automation: Clone → Sysprep → Wait → Ready for Ansible
#
# Usage: ./deploy_all.sh
# Run dari Proxmox host (node)
# ==============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     LKS Windows Server - Full Deploy Automation         ║"
echo "║                                                          ║"
echo "║  Step 1: Clone VMs from template                        ║"
echo "║  Step 2: Sysprep generalize (fix SID)                   ║"
echo "║  Step 3: Wait for VMs to be ready                       ║"
echo "║  Step 4: Ready for Ansible!                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Start full deployment? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ===================== STEP 1: Clone VMs =====================
echo ""
echo -e "${CYAN}═══ STEP 1/3: Cloning VMs from template ═══${NC}"
echo ""

bash "${SCRIPT_DIR}/clone_vms.sh"

# ===================== STEP 2: Wait for VMs to boot =====================
echo ""
echo -e "${CYAN}═══ STEP 2/3: Waiting for VMs to boot (60s) ═══${NC}"
echo ""
echo "Waiting for Windows to fully boot..."

for i in $(seq 60 -1 1); do
    echo -ne "\r  Boot countdown: ${i}s remaining...  "
    sleep 1
done
echo ""

# ===================== STEP 3: Generalize VMs =====================
echo ""
echo -e "${CYAN}═══ STEP 3/3: Running sysprep generalize ═══${NC}"
echo ""

bash "${SCRIPT_DIR}/generalize_vms.sh"

# ===================== STEP 4: Final Wait =====================
echo ""
echo -e "${CYAN}═══ Waiting for VMs to finish OOBE (120s) ═══${NC}"
echo ""

for i in $(seq 120 -1 1); do
    echo -ne "\r  OOBE countdown: ${i}s remaining...  "
    sleep 1
done
echo ""

# ===================== DONE =====================
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║               ✅ DEPLOYMENT COMPLETE!                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  All VMs are ready with unique SIDs and WinRM enabled.  ║"
echo "║                                                          ║"
echo "║  VM IDs:                                                ║"
echo "║    101 - dc          (172.16.0.1)                       ║"
echo "║    102 - srv         (172.16.0.10)                      ║"
echo "║    103 - fw          (172.16.0.254)                     ║"
echo "║    104 - workstation (DHCP)                             ║"
echo "║                                                          ║"
echo "║  Next steps:                                            ║"
echo "║  1. SSH ke ansible-srv (172.16.0.151)                   ║"
echo "║  2. Copy playbooks: scp -r ansible/* ansible-srv:/etc/  ║"
echo "║  3. Test: ansible all -m win_ping                       ║"
echo "║  4. Run: ansible-playbook site.yml                      ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
