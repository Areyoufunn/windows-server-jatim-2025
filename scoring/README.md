# LKS Scoring System - Automated Grading for Juri

Sistem penilaian otomatis untuk soal LKS Windows Environment.
Menggunakan **Management Network (10.0.0.x)** agar selalu bisa connect.

## 🚀 Cara Pakai

```bash
# 1. Copy ke ansible-srv
scp -r scoring/* root@10.0.0.151:/etc/ansible/scoring/

# 2. SSH ke ansible-srv
ssh root@10.0.0.151

# 3. Jalankan scoring
cd /etc/ansible/scoring
ansible-playbook scoring.yml

# 4. Buka report di browser
# Output: /tmp/lks_scoring_report.html
```

## 🌐 Network yang Dipakai

Scoring mengakses host via **Management network** (bukan topologi):

| Host | Management IP | Keterangan |
|---|---|---|
| dc | **10.0.0.1** | Preconfigured, always available |
| srv | **10.0.0.2** | Preconfigured, always available |
| fw | **10.0.0.3** | Preconfigured, always available |
| workstation | **10.0.0.4** | Preconfigured, always available |
| ansible-srv | **localhost** | Ansible checks run locally |

> ⚠️ Meskipun koneksi via 10.0.0.x, pengecekan IP tetap **mengecek Ethernet0** (172.16.0.x) sesuai soal.

## 📊 Scoring (100 Points)

| Kategori | Poin | Host |
|---|---|---|
| Basic Configuration | 8 | All |
| Active Directory | 20 | DC |
| DNS Service | 14 | DC |
| Certificate Authority | 6 | DC |
| DHCP Service | 10 | FW |
| RAID Configuration | 5 | SRV |
| File Service | 13 | SRV |
| IIS Web Service | 10 | SRV |
| Routing & NAT | 6 | FW + WS |
| Ansible Playbooks | 8 | ansible-srv |
| **Total** | **100** | |

## 📁 Files

```
scoring/
├── ansible.cfg              # Config (pakai inventory lokal)
├── inventory.yml            # Inventory via Management IP
├── scoring.yml              # Master playbook
├── scoring_criteria.yml     # Definisi poin
├── checks/
│   ├── check_dc.yml         # AD, DNS, CA, GPO
│   ├── check_srv.yml        # RAID, File, IIS
│   ├── check_fw.yml         # DHCP, Routing
│   ├── check_workstation.yml # Internet access
│   └── check_ansible.yml    # Playbook existence
├── templates/
│   └── report.html.j2       # HTML report (dark theme)
└── README.md
```
