# Ansible Automation - Windows Server LKS 2025

Ansible playbooks untuk otomasi konfigurasi Windows Server sesuai soal LKS Provinsi 2025 - Modul Windows Environment.

## 📋 Prasyarat

### Ansible Server (ansible-srv)
```bash
# Install Ansible + WinRM dependencies
pip install ansible pywinrm
# Atau
apt install ansible python3-winrm
```

### Windows Server (Semua Host)
Jalankan script `enable_winrm.ps1` sebagai **Administrator** di setiap Windows Server:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\enable_winrm.ps1
```

## 🚀 Cara Penggunaan

### 1. Copy ke Ansible Server
```bash
# Copy semua file dari folder ini ke /etc/ansible/ di ansible-srv
scp -r ./* root@172.16.0.151:/etc/ansible/
```

### 2. Test Koneksi
```bash
ansible all -m win_ping
```

### 3. Jalankan Semua Konfigurasi
```bash
ansible-playbook site.yml
```

### 4. Jalankan Per-Fase (Opsional)
```bash
# Hanya basic configuration
ansible-playbook site.yml --tags "basic"

# Hanya Active Directory
ansible-playbook site.yml --tags "ad"

# Hanya DNS
ansible-playbook site.yml --tags "dns"

# Kombinasi
ansible-playbook site.yml --tags "basic,ad,dns"
```

## 📁 3 Playbook Wajib (Soal)

### 1. Install Features
```bash
ansible-playbook install_features.yml
```

### 2. DNS Record
```bash
ansible-playbook dns_record.yml -e record=test -e value=172.16.0.1
```

### 3. Shared Folder
```bash
# Dengan owner (full permission)
ansible-playbook shared_folder.yml \
  -e share_name=Test \
  -e path='C:/sharing/test' \
  -e access='"Domain Users"' \
  -e owner='Manager'

# Tanpa owner
ansible-playbook shared_folder.yml \
  -e share_name=Public \
  -e path='C:/sharing/public' \
  -e access='"Domain Users"'
```

## 🏗️ Urutan Eksekusi (site.yml)

| Phase | Target | Deskripsi |
|-------|--------|-----------|
| 1 | All Windows | Basic Config (hostname, IP, timezone) |
| 2 | DC | Active Directory |
| 3 | DC | DNS Service |
| 4 | DC | Certificate Authority |
| 5 | DC | Group Policy |
| 6 | SRV, FW, WS | Domain Join |
| 7 | FW | Routing & NAT |
| 8 | FW | DHCP Service |
| 9 | SRV | RAID (Storage Spaces) |
| 10 | SRV | File Service |
| 11 | SRV | IIS Web Service |

## ⚠️ Catatan Penting

1. **Jalankan `enable_winrm.ps1`** di setiap Windows Server sebelum menjalankan Ansible
2. **RAID**: Pastikan 3 disk tambahan (10GB) sudah di-attach ke SRV di Proxmox sebelum menjalankan playbook
3. **Urutan penting**: Phase 2 (AD) harus selesai sebelum Phase 6 (Domain Join)
4. **Inventory**: Sesuaikan `inventory/hosts.yml` jika IP address berbeda dari default
5. **Password default**: `P@ssw0rd2025` untuk admin, `Skill39!` untuk AD users
