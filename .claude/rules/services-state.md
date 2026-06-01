# État des services — À lire avant toute action

## ⚠️ Containers déplacés récemment

Ne pas supposer que l'ancienne configuration est correcte. Les services ont changé de VM.

### Ce qui a changé (2026-05-27)

| Service | Ancienne VM | VM actuelle |
|---------|-------------|-------------|
| Kibana :5601 | ops-vm | **bastion** |
| Logstash :5044 | ops-vm | **supprimé** |
| Filebeat output | → Logstash | → **Elasticsearch directement** |
| Protocole | HTTP | **HTTPS partout (CA interne)** |

### Localisation actuelle de chaque service

**ops-vm (172.16.0.253) — PVE1**
- Elasticsearch :9200 HTTPS ✅
- Vault :8200 HTTPS ✅
- Filebeat (systemd) ✅
- ⚠️ Disk 87% plein — ne pas ajouter de container sans vérifier l'espace

**bastion (10.255.255.249) — PVE2 DMZ (vmbr3)**
- Kibana :5601 HTTPS ✅
- Filebeat (systemd) ✅
- Disk 73% plein

**web (192.168.255.243) — PVE2 LAN (vmbr4)**
- Site web uniquement — Docker non installé
- Disk 63% libre

**services-vm (172.16.0.241) — ⚠️ HORS LIGNE**
- Inaccessible (réseau KO sur PVE1)
- Netbox prévu ici (PR #72) — bloqué

### TLS — tous les services en HTTPS

CA interne : `~/.ansible-tls/ca.crt` (sur le controller Ansible, hors repo).
Certs déployés dans `/etc/ssl/internal/` sur chaque VM.

Tunnels SSH requis pour accéder aux services (ProxyJump via Proxmox — les deux sites sont sur 51.75.128.134) :
- ES + Vault (ops-vm) : `-J root@51.75.128.134 ubuntu@172.16.0.x` avec ports `-L 9200:... -L 8200:...`
- Kibana (bastion) : `-J root@51.75.128.134 ubuntu@10.255.255.249` avec port `-L 5601:...`

### Vérifier l'espace disque avant tout déploiement

```bash
cd ansible/
ansible ops:bastion:web -m shell -a "df -h /"
```
