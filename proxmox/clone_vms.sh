#!/bin/bash
# ==============================================================
# Proxmox VM Clone Script for LKS Windows Server
# Clone Windows Server template ke beberapa VM sekaligus
#
# Usage: ./clone_vms.sh
# Run dari Proxmox host (node)
# ==============================================================

set -e

# ===================== KONFIGURASI =====================
# Sesuaikan dengan environment Proxmox Anda

# Template VM ID (Windows Server yang sudah di-install & sysprep)
TEMPLATE_VMID=9000

# Proxmox storage untuk disk clone
STORAGE="local-lvm"       # Ganti sesuai storage Anda (local-lvm, ceph, zfs, dll)

# Proxmox node name
NODE="pve"                 # Ganti sesuai hostname node Proxmox

# Pool resource (opsional, kosongkan jika tidak pakai pool)
POOL=""

# ===================== VM DEFINITIONS =====================
# Format: VMID|HOSTNAME|MEMORY(MB)|CORES|DESCRIPTION
declare -a VMS=(
    "101|dc|4096|2|Domain Controller - dc.itnsa.id"
    "102|srv|4096|2|Application Server - srv.itnsa.id"
    "103|fw|2048|2|Firewall/Router - fw.itnsa.id"
    "104|workstation|2048|2|Workstation - workstation.itnsa.id"
)

# ===================== NETWORK CONFIG =====================
# Bridge untuk setiap interface
INTERNAL_BRIDGE="vmbr1"    # Bridge untuk jaringan internal 172.16.0.0/24
EXTERNAL_BRIDGE="vmbr0"    # Bridge untuk jaringan external 192.1.1.0/24
MANAGEMENT_BRIDGE="vmbr2"  # Bridge untuk management 10.0.0.0/24

# ===================== WARNA OUTPUT =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ===================== FUNCTIONS =====================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

check_template() {
    log_step "Checking template VM ${TEMPLATE_VMID}..."
    if ! qm status ${TEMPLATE_VMID} &>/dev/null; then
        log_error "Template VM ${TEMPLATE_VMID} not found!"
        log_error "Pastikan template VM sudah ada dan sudah di-sysprep."
        exit 1
    fi

    # Check if template is a template or regular VM
    local is_template=$(qm config ${TEMPLATE_VMID} | grep -c "template: 1" || true)
    if [ "$is_template" -eq 0 ]; then
        log_warn "VM ${TEMPLATE_VMID} is not marked as template."
        log_warn "Disarankan: qm template ${TEMPLATE_VMID}"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    log_info "Template ${TEMPLATE_VMID} is ready."
}

check_existing_vm() {
    local vmid=$1
    local hostname=$2

    if qm status ${vmid} &>/dev/null; then
        log_warn "VM ${vmid} (${hostname}) already exists!"
        read -p "  Delete and recreate? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stopping VM ${vmid}..."
            qm stop ${vmid} --skiplock 2>/dev/null || true
            sleep 3
            log_info "Destroying VM ${vmid}..."
            qm destroy ${vmid} --purge --skiplock 2>/dev/null || true
            sleep 2
        else
            log_info "Skipping VM ${vmid} (${hostname})"
            return 1
        fi
    fi
    return 0
}

clone_vm() {
    local vmid=$1
    local hostname=$2
    local memory=$3
    local cores=$4
    local desc=$5

    log_step "Cloning template to VM ${vmid} (${hostname})..."

    # Full clone from template
    local pool_arg=""
    if [ -n "$POOL" ]; then
        pool_arg="--pool ${POOL}"
    fi

    qm clone ${TEMPLATE_VMID} ${vmid} \
        --name "${hostname}" \
        --full true \
        --storage ${STORAGE} \
        --description "${desc}" \
        ${pool_arg}

    log_info "Clone VM ${vmid} (${hostname}) created."

    # Set memory and CPU
    log_info "  Setting ${memory}MB RAM, ${cores} cores..."
    qm set ${vmid} --memory ${memory} --cores ${cores} --sockets 1

    # Configure network adapters
    configure_network ${vmid} ${hostname}

    log_info "  VM ${vmid} (${hostname}) configured successfully."
}

configure_network() {
    local vmid=$1
    local hostname=$2

    log_info "  Configuring network for ${hostname}..."

    case ${hostname} in
        dc)
            # DC: Ethernet0 (Internal) + Management
            qm set ${vmid} --net0 "virtio,bridge=${INTERNAL_BRIDGE}"
            qm set ${vmid} --net1 "virtio,bridge=${MANAGEMENT_BRIDGE}"
            ;;
        srv)
            # SRV: Ethernet0 (Internal) + Management
            qm set ${vmid} --net0 "virtio,bridge=${INTERNAL_BRIDGE}"
            qm set ${vmid} --net1 "virtio,bridge=${MANAGEMENT_BRIDGE}"
            ;;
        fw)
            # FW: Ethernet0 (Internal) + Ethernet1 (External) + Management
            qm set ${vmid} --net0 "virtio,bridge=${INTERNAL_BRIDGE}"
            qm set ${vmid} --net1 "virtio,bridge=${EXTERNAL_BRIDGE}"
            qm set ${vmid} --net2 "virtio,bridge=${MANAGEMENT_BRIDGE}"
            ;;
        workstation)
            # Workstation: Ethernet0 (Internal/DHCP) + Management
            qm set ${vmid} --net0 "virtio,bridge=${INTERNAL_BRIDGE}"
            qm set ${vmid} --net1 "virtio,bridge=${MANAGEMENT_BRIDGE}"
            ;;
    esac
}

add_extra_disks() {
    local vmid=$1
    local hostname=$2

    # SRV needs 3 extra 10GB disks for RAID
    if [ "${hostname}" == "srv" ]; then
        log_info "  Adding 3 extra 10GB disks for RAID on SRV..."
        qm set ${vmid} --scsi1 "${STORAGE}:10"
        qm set ${vmid} --scsi2 "${STORAGE}:10"
        qm set ${vmid} --scsi3 "${STORAGE}:10"
        log_info "  3 extra disks added to SRV."
    fi
}

start_vm() {
    local vmid=$1
    local hostname=$2

    log_info "  Starting VM ${vmid} (${hostname})..."
    qm start ${vmid}
}

# ===================== MAIN =====================

echo "============================================================"
echo "  Proxmox VM Clone Script - LKS Windows Server 2025"
echo "============================================================"
echo ""
echo "Template VMID : ${TEMPLATE_VMID}"
echo "Storage       : ${STORAGE}"
echo "Node          : ${NODE}"
echo "VMs to create : ${#VMS[@]}"
echo ""

# Step 1: Check template
check_template

# Step 2: Clone each VM
echo ""
log_step "Starting clone process..."
echo ""

for vm_def in "${VMS[@]}"; do
    IFS='|' read -r vmid hostname memory cores desc <<< "${vm_def}"

    echo "------------------------------------------------------------"
    echo "  VM: ${hostname} (ID: ${vmid})"
    echo "------------------------------------------------------------"

    # Check if VM already exists
    if ! check_existing_vm ${vmid} ${hostname}; then
        continue
    fi

    # Clone VM
    clone_vm ${vmid} ${hostname} ${memory} ${cores} "${desc}"

    # Add extra disks (for SRV)
    add_extra_disks ${vmid} ${hostname}

    # Start VM
    start_vm ${vmid} ${hostname}

    echo ""
done

echo "============================================================"
log_info "All VMs cloned and started!"
echo ""
echo "  Next steps:"
echo "  1. Wait for VMs to boot to OOBE/sysprep"
echo "  2. Run generalize script: ./generalize_vms.sh"
echo "  3. Or manually run sysprep on each VM"
echo "============================================================"
