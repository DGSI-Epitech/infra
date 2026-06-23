# Documentation des Règles de Filtrage pfSense

Ce document détaille la matrice des flux et les règles de filtrage (firewall rules) configurées sur les deux pare-feux pfSense de l'infrastructure : **pfSense OP** (Site On-Premises) et **pfSense Cloud** (Site Cloud).

---

## 1. pfSense OP (Site On-Premises — Client VPN)

Le pfSense On-Premises agit comme client OpenVPN. Il établit la connexion sortante vers le pfSense Cloud.

### Interface WAN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow SSH WAN** | Pass | TCP | Any | Any | 22 | Permet l'administration SSH externe (depuis le bastion/contrôleur). |
| **Allow HTTPS WAN** | Pass | TCP | Any | Any | 443 | Accès à la console d'administration WebGUI. |
| *Allow OpenVPN 1194* | **Absent** | UDP | Any | Any | 1194 | **Supprimé (remédié)** : Inutile en entrée car ce site est client OpenVPN. |

### Interface LAN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow LAN to WAN** | Pass | Any | Any | Any | Any | Autorise toutes les connexions sortantes depuis le LAN local (`172.16.0.240/28`). |

### Interface OPENVPN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow OpenVPN inter-sites** | Pass | Any | Any | Any | Any | Autorise le trafic entrant en provenance du tunnel VPN inter-sites. |

---

## 2. pfSense Cloud (Site Cloud — Serveur VPN)

Le pfSense Cloud héberge la DMZ (contenant le bastion Teleport) et le LAN Cloud (contenant le serveur web). Il fait office de serveur OpenVPN.

### Interface WAN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow SSH WAN** | Pass | TCP | Any | Any | 22 | Accès d'administration SSH. |
| **Allow HTTPS WAN** | Pass | TCP | Any | Any | 443 | Accès à la console d'administration WebGUI. |
| **Allow OpenVPN 1194** | Pass | UDP | Any | Any | 1194 | Permet la connexion entrante du client OpenVPN OP. |

### Interface DMZ (OPT1) — *Ordre d'évaluation critique*
L'ordre d'application des règles ci-dessous est strict (première correspondance gagnante).

| # | Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **1** | *Default allow DMZ to any* | **Absent** | Any | Any | Any | Any | **Supprimé (remédié)** : Règle par défaut non sécurisée. |
| **2** | **Allow Teleport DMZ to LAN nodes** | Pass | TCP | Any | `192.168.255.240/28` (LAN Cloud) | 3022 | Permet au bastion Teleport de joindre les agents SSH des VM du LAN Cloud. |
| **3** | **Block DMZ to LAN** | Block | Any | Any | `192.168.255.240/28` (LAN Cloud) | Any | **Ségrégation DMZ** : Empêche le bastion de joindre d'autres ports/services du LAN Cloud. |
| **4** | **Allow DMZ to OP LAN VPN** | Pass | Any | `10.255.255.248/29` (DMZ Cloud) | `172.16.0.240/28` (LAN OP) | Any | Permet au bastion d'envoyer ses logs à Elasticsearch sur `ops-vm` via le VPN. |
| **5** | **Allow DMZ to Internet** | Pass | Any | Any | Any | Any | Permet aux serveurs de la DMZ d'accéder à Internet (mises à jour, etc.). |

### Interface LAN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow LAN to ANY** | Pass | Any | Any | Any | Any | Autorise le trafic sortant du LAN Cloud (`192.168.255.240/28`) vers toutes destinations. |

### Interface OPENVPN
| Règle / Description | Action | Protocole | Source | Destination | Port Dest | Commentaire / Rôle |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Allow OpenVPN inter-sites** | Pass | Any | Any | Any | Any | Autorise le trafic entrant en provenance du tunnel VPN inter-sites. |
