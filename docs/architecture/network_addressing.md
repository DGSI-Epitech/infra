# Adressage réseau

## Vue d'ensemble

```
Internet
    │
    ├── PVE1 (On-premise)  WAN: 5.196.45.8
    │       │
    │       └── pfSense S1 (op.local)
    │               │
    │               └── LAN: 172.16.255.240/28
    │                       ├── 172.16.255.242  services-vm  (Netbox, website)
    │                       └── 172.16.255.243  vault-vm     (Vault, Elastic)
    │
    └── PVE2 (Cloud)       WAN: 5.196.50.52
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
| URL publique | `https://ns3050272.ip-51-255-76.eu:8006` |
| IP locale (VMware) | `192.168.139.128` |
| Nœud | `pve` |

### pfSense S1

| Interface | Réseau | Valeur |
|---|---|---|
| WAN | IP publique routable | `5.196.45.8` |
| LAN | Réseau | `172.16.255.240/28` |
| LAN | Gateway | `172.16.255.254` |
| LAN | Broadcast | `172.16.255.255` |
| LAN | Masque | `255.255.255.240` |
| LAN | Adresses utilisables | 13 (`172.16.255.241` → `172.16.255.253`) |
| DNS cible | Via VPN | `192.168.255.254` |

Domaine local : `op.local`

### VMs PVE1

| VM | ID Proxmox | IP | Gateway | Rôle |
|---|---|---|---|---|
| ubuntu-template | 9000 | — | — | Template de base (ne pas démarrer) |
| services-vm | 200 | `172.16.255.242/28` | `172.16.255.254` | Netbox, website |
| vault-vm | 201 | `172.16.255.243/28` | `172.16.255.254` | HashiCorp Vault, Elastic |

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
| Broadcast | `10.255.255.255` |
| Masque | `255.255.255.248` |
| Adresses utilisables | 5 (`10.255.255.249` → `10.255.255.253`) |

**LAN**

| Champ | Valeur |
|---|---|
| Réseau | `192.168.255.240/28` |
| Gateway | `192.168.255.254` |
| Broadcast | `192.168.255.255` |
| Masque | `255.255.255.240` |
| Adresses utilisables | 13 (`192.168.255.241` → `192.168.255.253`) |
| DNS cible | `172.16.255.254` (via VPN vers PVE1) |

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
