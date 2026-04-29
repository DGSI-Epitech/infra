# Adressage réseau

## Vue d'ensemble

```
Internet
    │
    ├── PVE1 (On-premise)  IP publique: 51.75.128.134
    │       │
    │       └── pfSense S1 (op.local)
    │               │
    │               └── LAN: 172.16.0.0/24
    │                       ├── 172.16.0.241  services-vm  (Netbox, website)
    │                       └── 172.16.0.242  vault-vm     (HashiCorp Vault)
    │
    └── PVE2 (Cloud)       IP publique: 5.196.50.52
            │
            └── pfSense S2 (cloud.local)
                    ├── DMZ: 10.255.255.248/29
                    │       └── 10.255.255.249  Teleport (bastion SSH)
                    └── LAN: 192.168.255.240/28
                            └── 192.168.255.243  website

OpenVPN: 10.3.3.0/29 (tunnel inter-sites)
```

---

## Site 1 — PVE1 On-premise

### Proxmox

| Champ | Valeur |
|---|---|
| IP publique | `51.75.128.134` |
| Nœud | `proxmox-site1` |

### pfSense S1

| Interface | Valeur |
|---|---|
| WAN | `vmbr0` (IP publique Proxmox) |
| LAN bridge | `vmbr1` |
| LAN IP (gateway) | `172.16.0.254/24` |
| LAN réseau | `172.16.0.0/24` |
| DHCP range | `172.16.0.241` → `172.16.0.253` |
| DNS | `1.1.1.1`, `8.8.8.8` |

Domaine local : `op.local`

### VMs PVE1

| VM | ID Proxmox | IP | Gateway | Rôle |
|---|---|---|---|---|
| ubuntu-template | 1000 | — | — | Template de base (ne pas démarrer) |
| pfsense-template | 2000 | — | — | Template pfSense (ne pas démarrer) |
| pfsense-fw-01 | 2100 | `172.16.0.254` | — | Pare-feu LAN/WAN |
| services-vm | 1100 | `172.16.0.241/24` | `172.16.0.254` | Netbox, website |
| vault-vm | 1200 | `172.16.0.242/24` | `172.16.0.254` | HashiCorp Vault |

> Les IDs Proxmox correspondent aux valeurs par défaut de `config.env.example`. Ils sont configurables via `config.env`.

---

## Site 2 — PVE2 Cloud

### Proxmox

| Champ | Valeur |
|---|---|
| URL publique | `https://ns3183326.ip-146-59-253.eu:8006` |
| Nœud | `pve` |

### pfSense S2

**DMZ**

| Champ | Valeur |
|---|---|
| Réseau | `10.255.255.248/29` |
| Gateway | `10.255.255.254` |
| Adresses utilisables | 5 (`10.255.255.249` → `10.255.255.253`) |

**LAN**

| Champ | Valeur |
|---|---|
| Réseau | `192.168.255.240/28` |
| Gateway | `192.168.255.254` |
| Adresses utilisables | 13 (`192.168.255.241` → `192.168.255.253`) |

Domaine local : `cloud.local`

### VMs PVE2

| VM | IP | Interface | Gateway | Rôle |
|---|---|---|---|---|
| Teleport | `10.255.255.249` | DMZ | `10.255.255.254` | Bastion SSH |
| website | `192.168.255.243` | LAN | `192.168.255.254` | Site web |

---

## Tunnel VPN inter-sites

| Champ | Valeur |
|---|---|
| Réseau | `10.3.3.0/29` |
| Protocole | OpenVPN |
| Rôle | Liaison chiffrée entre PVE1 et PVE2 |
| Côté PVE1 | pfSense S1 (`pfsense-fw-01`) |
| Côté PVE2 | pfSense S2 |

---

## Accès SSH aux VMs PVE1

Les VMs Ubuntu (`services-vm`, `vault-vm`) sont sur `vmbr1`, réseau privé inaccessible directement. Tout accès passe par Proxmox comme ProxyJump :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.241   # services-vm
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242   # vault-vm
```
