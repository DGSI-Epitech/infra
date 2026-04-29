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
| services-vm | 1100 | DHCP (`172.16.0.241`–`172.16.0.253`) | `172.16.0.254` | Netbox, website |
| vault-vm | 1200 | DHCP (`172.16.0.241`–`172.16.0.253`) | `172.16.0.254` | HashiCorp Vault |

> Les IDs Proxmox correspondent aux valeurs par défaut de `config.env.example`. Ils sont configurables via `config.env`.

> Les IPs de `services-vm` et `vault-vm` sont assignées dynamiquement par le DHCP de pfSense. `deploy.sh` les découvre automatiquement via le QEMU guest agent après le boot. Voir `docs/decisions/DECISIONS.md` — section *IPs des VMs PVE1 — passage de statique à DHCP*.

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

Les VMs Ubuntu (`services-vm`, `vault-vm`) sont sur `vmbr1`, réseau privé inaccessible directement. Tout accès passe par Proxmox comme ProxyJump.

Les IPs étant assignées par DHCP, récupère l'IP courante via l'API Proxmox avant de te connecter :

```bash
# Récupérer l'IP d'une VM (remplace VMID par 1100 ou 1200)
curl -s -k -b "PVEAuthCookie=<ticket>" \
  https://<PROXMOX_HOST>:8006/api2/json/nodes/<node>/qemu/<VMID>/agent/network-get-interfaces

# Connexion SSH une fois l'IP connue
ssh -o ProxyJump=root@<PROXMOX_HOST> ubuntu@<IP_VM>
```

Lors d'un `./deploy.sh` complet, la découverte est automatique — les IPs sont passées à Ansible sans intervention manuelle.
