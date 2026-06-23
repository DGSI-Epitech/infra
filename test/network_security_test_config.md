# Network & Security Testing Configuration

## Endpoints & Credentials

### Site 1 (PVE1 @ 51.75.128.134)
- **pfSense-OP** (gateway): `192.168.255.254` (admin)
- **ops-vm** (internal): `172.16.0.253` (ubuntu)
- **Services**: Vault (8200), Elasticsearch (9200), Filebeat
- **SSH ProxyJump**: `-J admin@192.168.255.254`

### Site 2 (PVE2 @ 51.75.128.134)
- **pfSense-Cloud** (gateway): `192.168.255.254` (admin)
- **bastion** (DMZ): `10.255.255.249` (ubuntu)
- **web** (LAN): `192.168.255.243` (via web project)
- **Services**: Kibana (5601), Filebeat
- **SSH ProxyJump**: `-J admin@192.168.255.254` (via PVE1 then cross-VPN)

### Planned (Currently Offline)
- **services-vm** (S1 DMZ): `172.16.0.241` (dgsi-cloud)
  - Status: OFFLINE - network issue on PVE1
  - See: `services-state.md`

---

## TLS/HTTPS Configuration

All services use internal CA certificates:
- **CA certificate**: `~/.ansible-tls/ca.crt` (external to repo, on Ansible controller)
- **Deployment path**: `/etc/ssl/internal/` on each VM
- **Trust setup**: Must import CA cert for local testing tools (curl, browsers, etc.)

### Testing with curl
```bash
# Import CA for curl
export CURL_CA_BUNDLE=/path/to/ca.crt

# Test Vault HTTPS
curl --cacert /path/to/ca.crt https://172.16.0.253:8200/v1/sys/health

# Test Elasticsearch HTTPS
curl --cacert /path/to/ca.crt https://172.16.0.253:9200/
```

---

## VPN Configuration

### IPsec Tunnel Status
- **Tunnel**: PVE1 (51.75.128.134:500) ↔ PVE2 (51.75.128.134:500)
- **Protocol**: IPsec (IKEv2)
- **Ports**: UDP 500 (IKE), UDP 4500 (NAT-T)
- **Lifetime**: Phase 1 & 2 SA established

### Verify VPN Health
```bash
ssh admin@192.168.255.254

# pfSense CLI equivalent
# ipsecctl -sa          # List all SAs
# ipsecctl -f           # Rekey all SAs
# ipsecctl -D           # Disable all SAs
```

---

## DNS Configuration

### Nameserver Setup
- **S1 primary**: pfSense-OP resolver (172.16.0.1 for internal LAN)
- **S2 primary**: pfSense-Cloud resolver (10.255.255.1 for internal LAN)
- **S1 LAN**: ops-vm, services-vm use pfSense-OP nameserver
- **S2 DMZ**: bastion uses pfSense-Cloud nameserver
- **S2 LAN**: web uses pfSense-Cloud nameserver

### Expected Records (Unbound forward zones)
```
vault.internal          → 172.16.0.253 (ops-vm, S1)
elasticsearch.internal  → 172.16.0.253 (ops-vm, S1)
kibana.internal         → 10.255.255.249 (bastion, S2 DMZ)
web.internal            → 192.168.255.243 (web-vm, S2 LAN)
services-vm.internal    → 172.16.0.241 (services-vm, S1 DMZ - OFFLINE)

teleport.internal       → TBD (Teleport not yet deployed)
```

### DNS Split-horizon
- Queries for `*.internal` → forwarded to local pfSense Unbound
- Queries for `*.proxmox.local` → forwarded to Proxmox DNS (if configured)
- Public DNS → ISP or CloudFlare (1.1.1.1)

---

## Firewall Rules Summary

### pfSense-OP (WAN inbound)
```
Allow:
  - UDP 500  (IPsec IKE)
  - UDP 4500 (IPsec NAT-T)
  - TCP 443  (API/UI - optional, usually for remote management)
  
Deny/Filter:
  - TCP 22 (SSH - allow only from trusted static IP)
  - TCP 80 (HTTP - redirect to HTTPS)
  - All other WAN inbound
```

### pfSense-OP (LAN-to-LAN cross-site)
```
Allow:
  - TCP 22   (SSH ops-vm ↔ bastion)
  - TCP 443  (HTTPS services)
  - TCP 8200 (Vault ops-vm → bastion)
  - TCP 9200 (Elasticsearch ops-vm → bastion)
  - TCP 5601 (Kibana bastion → web or external)
  
Deny:
  - TCP 5044 (Logstash - service discontinued)
  - All other inter-site
```

---

## Teleport Configuration

### Current Status
- **Status**: NOT DEPLOYED (identified in tests as missing)
- **Planned deployment**: Bastion or ops-vm as proxy
- **Dependencies**: Teleport server, Teleport client (tsh)

### Testing Prerequisites (if Teleport deployed)
1. Teleport config file: `/etc/teleport.yaml`
2. Certificates: `/etc/teleport/certs/`
3. CA bundle: `/etc/teleport/ca.crt`
4. Auth backend: OIDC, LDAP, or local users

### SSH via Teleport (once deployed)
```bash
# Login to Teleport
tsh login --proxy=<teleport-proxy>:3080

# List nodes
tsh ls

# SSH via Teleport
tsh ssh ubuntu@ops-vm

# Port forwarding via Teleport
tsh proxy ssh -L 8200:vault.internal:8200 ubuntu@ops-vm
```

---

## Service Endpoints Checklist

| Service | Protocol | Host | Port | Status | Notes |
|---------|----------|------|------|--------|-------|
| pfSense-OP | SSH | 192.168.255.254 | 22 | ✅ | External admin access |
| pfSense-Cloud | SSH | 192.168.255.254 | 22 | ✅ | External admin access |
| ops-vm SSH | SSH | 172.16.0.253 | 22 | ✅ | Via ProxyJump through pfSense |
| bastion SSH | SSH | 10.255.255.249 | 22 | ✅ | Via ProxyJump through pfSense |
| Vault | HTTPS | 172.16.0.253 | 8200 | ✅ | ops-vm, CA cert required |
| Elasticsearch | HTTPS | 172.16.0.253 | 9200 | ✅ | ops-vm, CA cert required |
| Kibana | HTTPS | 10.255.255.249 | 5601 | ✅ | bastion, CA cert required |
| Filebeat (ops-vm) | Systemd | 172.16.0.253 | - | ✅ | Ships logs to ES |
| Filebeat (bastion) | Systemd | 10.255.255.249 | - | ✅ | Ships logs to ES |
| services-vm SSH | SSH | 172.16.0.241 | 22 | ❌ | OFFLINE - network issue |
| Teleport | HTTPS | TBD | 3080 | ❌ | Not deployed |
| Logstash | TCP | - | 5044 | ❌ | Discontinued (replaced by ES direct) |

---

## Debugging Commands

### SSH Troubleshooting
```bash
# Verbose SSH (debug connection)
ssh -vvv -J admin@192.168.255.254 ubuntu@172.16.0.253

# Check SSH key permissions
ssh-keygen -l -f ~/.ssh/id_rsa

# Test key-based auth
ssh -i ~/.ssh/id_rsa -J admin@192.168.255.254 ubuntu@172.16.0.253 "echo OK"
```

### VPN Troubleshooting (pfSense)
```bash
ssh admin@192.168.255.254

# Check IPsec status (pfSense CLI)
ipsecctl -sa

# Check IKE daemon logs
tail -f /var/log/charon.log

# Rekey tunnels (force renegotiation)
ipsecctl -f

# Disable and re-enable
ipsecctl -D
sleep 2
ipsecctl -f
```

### DNS Troubleshooting
```bash
# On a VM, check nameserver
cat /etc/resolv.conf
resolvectl status

# Test DNS resolution
nslookup vault.internal
dig vault.internal +trace

# On pfSense (Unbound config)
# Check /etc/unbound/unbound.conf for forward zones
```

### Firewall Testing
```bash
# Scan from bastion to ops-vm
nmap -p 22,443,8200,9200,5044 172.16.0.253

# Test specific port connectivity
nc -zv 172.16.0.253 8200

# Check listening ports on ops-vm
sudo ss -tlnp | grep -E ":8200|:9200"
```

---

## Environment Variables & Secrets

### For Testing Scripts
```bash
# SSH Key (if not default)
export SSH_KEY_PATH=~/.ssh/infra_rsa

# CA Certificate for HTTPS
export CURL_CA_BUNDLE=~/.ansible-tls/ca.crt

# Vault credentials (if needed for tests)
export VAULT_ADDR=https://172.16.0.253:8200
export VAULT_CACERT=~/.ansible-tls/ca.crt
export VAULT_TOKEN=<token>
```

---

## Next Steps After Testing

1. **Document Issues**: Add findings to `NETWORK_SECURITY_TESTS.md` section 6
2. **Create Fixes**: 
   - Ansible playbooks for DNS records
   - Firewall rule updates
   - Teleport deployment (if needed)
3. **Re-test**: Verify all fixes pass tests again
4. **PR Review**: Submit results and fixes for code review
5. **Deploy to Prod**: Once validated, deploy via `ansible-playbook` or Terraform

