#!/bin/bash
# ==============================================================
# Generalize Windows VMs via Proxmox QEMU Guest Agent
# Menjalankan sysprep + unattend.xml pada setiap VM yang sudah di-clone
#
# PRASYARAT:
# - QEMU Guest Agent harus terinstall di template Windows Server
# - VMs harus dalam keadaan running
#
# Usage: ./generalize_vms.sh
# Run dari Proxmox host (node)
# ==============================================================

set -e

# ===================== KONFIGURASI =====================
ADMIN_PASS="P@ssw0rd2025"
TIMEZONE="SE Asia Standard Time"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# VM Definitions: VMID|HOSTNAME
declare -a VMS=(
    "101|dc"
    "102|srv"
    "103|fw"
    "104|workstation"
)

# ===================== WARNA =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

# ===================== FUNCTIONS =====================

generate_unattend() {
    local hostname=$1
    local output_file=$2

    log_info "  Generating unattend.xml for ${hostname}..."

    # Read template and replace variables
    sed -e "s/%%HOSTNAME%%/${hostname}/g" \
        -e "s/%%ADMIN_PASS%%/${ADMIN_PASS}/g" \
        -e "s/%%TIMEZONE%%/${TIMEZONE}/g" \
        "${SCRIPT_DIR}/unattend_template.xml" > "${output_file}"

    log_info "  unattend.xml generated: ${output_file}"
}

check_guest_agent() {
    local vmid=$1
    local hostname=$2
    local max_wait=120
    local elapsed=0

    log_info "  Waiting for QEMU Guest Agent on ${hostname} (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        if qm agent ${vmid} ping &>/dev/null; then
            log_info "  Guest Agent is responding on ${hostname}!"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -ne "\r  Waiting... ${elapsed}s / ${max_wait}s"
    done

    echo ""
    log_error "  Guest Agent not responding on ${hostname} after ${max_wait}s"
    log_error "  Pastikan QEMU Guest Agent terinstall di Windows Server."
    log_error "  Install: https://pve.proxmox.com/wiki/Qemu-guest-agent"
    return 1
}

upload_unattend() {
    local vmid=$1
    local hostname=$2
    local local_file=$3

    log_info "  Uploading unattend.xml to ${hostname}..."

    # Upload unattend.xml ke Windows VM via Guest Agent
    # Gunakan base64 encode karena qm guest exec tidak support file upload langsung
    local content=$(base64 -w0 "${local_file}")

    qm guest exec ${vmid} -- powershell.exe -ExecutionPolicy Bypass -Command "
        \$bytes = [Convert]::FromBase64String('${content}')
        [IO.File]::WriteAllBytes('C:\\Windows\\Temp\\unattend.xml', \$bytes)
        Write-Output 'unattend.xml uploaded to C:\\Windows\\Temp\\unattend.xml'
    " 2>/dev/null

    log_info "  unattend.xml uploaded to C:\\Windows\\Temp\\unattend.xml"
}

run_sysprep() {
    local vmid=$1
    local hostname=$2

    log_step "  Running sysprep generalize on ${hostname}..."

    # Jalankan sysprep dengan unattend.xml
    # /generalize  = Reset SID (solusi masalah clone)
    # /oobe        = Boot ke Out-of-Box Experience
    # /shutdown    = Shutdown setelah sysprep
    # /unattend    = Gunakan answer file untuk otomasi OOBE
    qm guest exec ${vmid} -- powershell.exe -ExecutionPolicy Bypass -Command "
        # Kill any existing sysprep processes
        Get-Process -Name sysprep -ErrorAction SilentlyContinue | Stop-Process -Force

        # Clean up previous sysprep state if exists
        Remove-Item 'C:\\Windows\\System32\\Sysprep\\Panther\\*' -Recurse -Force -ErrorAction SilentlyContinue

        # Run sysprep
        Start-Process -FilePath 'C:\\Windows\\System32\\Sysprep\\sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /unattend:C:\\Windows\\Temp\\unattend.xml' -Wait
    " 2>/dev/null &

    log_info "  Sysprep started on ${hostname}. VM will shutdown when complete."
}

wait_for_shutdown() {
    local vmid=$1
    local hostname=$2
    local max_wait=300
    local elapsed=0

    log_info "  Waiting for ${hostname} to shutdown after sysprep (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        local status=$(qm status ${vmid} | awk '{print $2}')
        if [ "$status" == "stopped" ]; then
            log_info "  ${hostname} has shutdown successfully!"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo -ne "\r  Status: ${status} | Waiting... ${elapsed}s / ${max_wait}s"
    done

    echo ""
    log_warn "  ${hostname} did not shutdown within ${max_wait}s. Force stopping..."
    qm stop ${vmid} 2>/dev/null || true
    return 0
}

start_vm_after_sysprep() {
    local vmid=$1
    local hostname=$2

    log_info "  Starting ${hostname} after sysprep..."
    qm start ${vmid}
    log_info "  ${hostname} started! It will boot with new SID and hostname."
}

# ===================== MAIN =====================

echo "============================================================"
echo "  Proxmox Sysprep Generalize Script"
echo "  Solusi masalah SID duplikat pada clone Windows Server"
echo "============================================================"
echo ""
echo "  Proses yang akan dilakukan pada setiap VM:"
echo "  1. Generate unattend.xml dengan hostname spesifik"
echo "  2. Upload unattend.xml ke VM via QEMU Guest Agent"
echo "  3. Jalankan sysprep /generalize"
echo "  4. VM shutdown otomatis"
echo "  5. Start VM → boot dengan SID baru"
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Create temp directory for generated unattend files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

for vm_def in "${VMS[@]}"; do
    IFS='|' read -r vmid hostname <<< "${vm_def}"

    echo ""
    echo "------------------------------------------------------------"
    echo "  Processing: ${hostname} (VMID: ${vmid})"
    echo "------------------------------------------------------------"

    # Check VM is running
    local_status=$(qm status ${vmid} 2>/dev/null | awk '{print $2}' || echo "unknown")
    if [ "$local_status" != "running" ]; then
        log_warn "  VM ${vmid} (${hostname}) is not running (status: ${local_status})."
        log_info "  Starting VM..."
        qm start ${vmid} 2>/dev/null || true
        sleep 30
    fi

    # Step 1: Check Guest Agent
    if ! check_guest_agent ${vmid} ${hostname}; then
        log_error "  Skipping ${hostname} - Guest Agent not available"
        continue
    fi

    # Step 2: Generate unattend.xml
    local_unattend="${TEMP_DIR}/unattend_${hostname}.xml"
    generate_unattend ${hostname} ${local_unattend}

    # Step 3: Upload unattend.xml
    upload_unattend ${vmid} ${hostname} ${local_unattend}

    # Step 4: Run sysprep
    run_sysprep ${vmid} ${hostname}

    # Step 5: Wait for shutdown
    wait_for_shutdown ${vmid} ${hostname}

    # Step 6: Start VM
    start_vm_after_sysprep ${vmid} ${hostname}

    log_info "  ${hostname} is ready with new SID!"
done

echo ""
echo "============================================================"
log_info "All VMs generalized and restarted!"
echo ""
echo "  Setiap VM sekarang memiliki:"
echo "  - SID unik (bisa join domain)"
echo "  - Hostname sesuai soal"
echo "  - WinRM aktif (siap untuk Ansible)"
echo "  - Password: ${ADMIN_PASS}"
echo ""
echo "  Next step:"
echo "  - Tunggu semua VM selesai boot (~2-5 menit)"
echo "  - Test Ansible: ansible all -m win_ping"
echo "  - Jalankan: ansible-playbook site.yml"
echo "============================================================"
