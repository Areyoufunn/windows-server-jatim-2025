# Proxmox Clone & Sysprep Automation

Scripts untuk otomasi clone Windows Server dari template Proxmox dan menyelesaikan masalah SID duplikat.

## ⚠️ Masalah SID Duplikat

Saat Windows Server di-clone, **SID (Security Identifier)** ikut ter-clone sehingga semua VM punya SID yang sama. Ini menyebabkan:
- ❌ Gagal join domain (SID conflict)
- ❌ Masalah autentikasi Kerberos
- ❌ Konflik di Active Directory

**Solusi**: Jalankan `sysprep /generalize` → menghasilkan SID baru untuk setiap VM.

## 📋 Prasyarat

### Template Windows Server
1. Install Windows Server 2012/2016/2019/2022
2. Install **QEMU Guest Agent** (penting untuk otomasi!)
   ```powershell
   # Download dari: https://pve.proxmox.com/wiki/Qemu-guest-agent
   # Atau via Proxmox ISO: virtio-win
   ```
3. Enable QEMU Guest Agent di Proxmox:
   ```bash
   qm set <VMID> --agent 1
   ```
4. **JANGAN** sysprep template — biarkan script yang menjalankannya pada clone

### Proxmox Host
- Pastikan `qm` command tersedia (default di Proxmox)
- Script ini harus dijalankan dari **Proxmox node** (SSH ke node)

## 🚀 Cara Penggunaan

### Option 1: One-Click Deploy (Recommended)
```bash
# Copy semua file ke Proxmox host
scp -r proxmox/* root@proxmox-host:/root/lks-deploy/

# SSH ke Proxmox
ssh root@proxmox-host

# Jalankan
cd /root/lks-deploy
chmod +x *.sh
./deploy_all.sh
```

### Option 2: Step-by-Step
```bash
# Step 1: Clone VMs dari template
./clone_vms.sh

# Step 2: Tunggu VMs boot (~60 detik)
# Step 3: Generalize (sysprep) setiap VM
./generalize_vms.sh
```

## 📁 File

| File | Deskripsi |
|------|-----------|
| `clone_vms.sh` | Clone template ke 4 VM (dc, srv, fw, workstation) |
| `generalize_vms.sh` | Sysprep generalize via QEMU Guest Agent |
| `deploy_all.sh` | Master script (clone → sysprep → ready) |
| `unattend_template.xml` | Answer file untuk otomasi sysprep OOBE |

## ⚙️ Konfigurasi

Edit bagian atas `clone_vms.sh`:
```bash
TEMPLATE_VMID=9000          # ID template VM
STORAGE="local-lvm"          # Storage Proxmox
INTERNAL_BRIDGE="vmbr1"      # Bridge internal
EXTERNAL_BRIDGE="vmbr0"      # Bridge external
MANAGEMENT_BRIDGE="vmbr2"    # Bridge management
```

## 🔄 Alur Kerja

```
Template (VMID 9000)
  │
  ├─ clone_vms.sh ──→ 101 (dc) ──→ generalize ──→ SID baru ──→ ✅ Ready
  ├─ clone_vms.sh ──→ 102 (srv) ─→ generalize ──→ SID baru ──→ ✅ Ready
  ├─ clone_vms.sh ──→ 103 (fw) ──→ generalize ──→ SID baru ──→ ✅ Ready
  └─ clone_vms.sh ──→ 104 (ws) ──→ generalize ──→ SID baru ──→ ✅ Ready
                                                        │
                                                   ansible-playbook site.yml
```
