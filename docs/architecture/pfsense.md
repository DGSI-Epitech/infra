# pfSense 2.7.2 — Template Packer

Ce document explique comment fonctionne le build Packer pour créer le template pfSense sur Proxmox.

---

## Prérequis

Avant de lancer le build, les éléments suivants doivent exister sur Proxmox :

- **vmbr1** — bridge LAN interne (172.16.0.1/24)
- **vmbr2** — bridge transit Proxmox → pfSense WAN (10.0.0.1/30)
- **ISO pfSense** — uploadée dans le storage `local:iso/`
- **NAT activé** sur Proxmox pour router le trafic de vmbr2 vers internet

```bash
# Activer le NAT sur Proxmox (persistant via /etc/network/interfaces)
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 10.0.0.0/30 -o vmbr0 -j MASQUERADE
```

---

## Structure des fichiers

```
packer/pfsense-2.7/
├── pfsense-2.7.pkr.hcl        # Configuration Packer principale
├── pfsense-2.7.pkrvars.hcl    # Variables (jamais committé)
├── pfsense-2.7.pkrvars.hcl.example  # Exemple de variables
└── http/
    └── config.xml             # Configuration pfSense pré-définie
```

---

## Architecture réseau

```
Internet
    │
    ▼
Proxmox (vmbr0 — 51.x.x.x/24)
    │
    ├── vmbr2 (10.0.0.1/30) ──── pfSense WAN (10.0.0.2/30)
    │                                     │
    └── vmbr1 (172.16.0.1/24) ─── pfSense LAN (172.16.0.254/24)
                                          │
                                    VMs du LAN
                                 (172.16.0.241–253)
```

- **vmbr2** est un réseau de transit entre Proxmox et pfSense. Proxmox fait le NAT pour donner internet à pfSense.
- **vmbr1** est le réseau privé des VMs. pfSense y fait office de firewall.

---

## Fonctionnement du build

### 1. Packer installe pfSense

Le `boot_command` simule les touches clavier pour traverser l'installeur pfSense automatiquement :

| Touche | Action |
|--------|--------|
| `<enter>` | Accepte la licence |
| `<enter>` | Choisit "Install pfSense" |
| `<down><enter>` | Sélectionne "Auto (UFS)" |
| `<enter>` | "Entire Disk" |
| `<enter>` | "MBR Partition Table" |
| `<enter>` | "Finish" |
| `<enter><wait40s>` | "Commit" — écrit sur le disque |

### 2. Packer ouvre un shell FreeBSD

Après l'installation, pfSense propose de redémarrer ou d'ouvrir un shell. Packer choisit le shell via `<right><enter>`.

### 3. Packer injecte la configuration

Au lieu de modifier le `config.xml` via des commandes `sed` (fragile), Packer copie directement un `config.xml` pré-configuré depuis un CD attaché à la VM :

```bash
mount /dev/vtbd0s1a /mnt        # Monte le disque pfSense installé
mkdir -p /mnt/cdrom
mount -t cd9660 /dev/cd1 /mnt/cdrom  # Monte notre CD avec config.xml
cp /mnt/cdrom/config.xml /mnt/cf/conf/config.xml  # Copie la config
sync && sync                    # Force l'écriture sur disque
/sbin/shutdown -p now           # Éteint la VM → Packer crée le template
```

> **Pourquoi `cd1` et pas `cd0` ?**
> `cd0` correspond à l'ISO pfSense. Notre CD de config est attaché en second, donc sur `cd1`.

### 4. Packer convertit en template

Une fois la VM éteinte, Packer la convertit automatiquement en template Proxmox. Ce template peut ensuite être cloné par Terraform.

---

## Le fichier config.xml

Le fichier `http/config.xml` contient la configuration initiale de pfSense. Il a été généré en configurant pfSense manuellement, puis exporté.

### Ce qui est configuré

| Paramètre | Valeur |
|-----------|--------|
| WAN interface | `vtnet0` (vmbr2) |
| WAN IP | `10.0.0.2/30` |
| WAN gateway | `10.0.0.1` (Proxmox vmbr2) |
| LAN interface | `vtnet1` (vmbr1) |
| LAN IP | `172.16.0.254/24` |
| DHCP range | `172.16.0.241` → `172.16.0.253` |
| DNS | `1.1.1.1`, `8.8.8.8` |
| SSH | Activé |
| Wizard | Marqué comme complété |

> **Note** : Le fichier ne contient pas de certificat SSL. pfSense en génère un nouveau automatiquement au premier démarrage.

---

## Variables requises

Copier `pfsense-2.7.pkrvars.hcl.example` en `pfsense-2.7.pkrvars.hcl` et remplir :

```hcl
proxmox_url        = "https://IP_PROXMOX:8006/api2/json"
proxmox_username   = "root@pam"
proxmox_password   = "MON_MOT_DE_PASSE"
proxmox_node       = "proxmox-site1"
proxmox_storage_vm = "local"
template_vm_id     = 200
```

> ⚠️ Ne jamais committer `pfsense-2.7.pkrvars.hcl` — il est dans le `.gitignore`.

---

## Lancer le build

```bash
cd packer/pfsense-2.7
packer init .
packer validate -var-file="pfsense-2.7.pkrvars.hcl" pfsense-2.7.pkr.hcl
packer build -var-file="pfsense-2.7.pkrvars.hcl" pfsense-2.7.pkr.hcl
```

> **Timeout réseau** : Si le build échoue avec `operation timed out` pendant le `boot_command`, ouvrir un tunnel SSH dans un terminal séparé avant de relancer :
> ```bash
> ssh -L 8006:localhost:8006 -N root@IP_PROXMOX
> # Puis changer proxmox_url en https://localhost:8006/api2/json
> ```

---

## Résultat

À la fin du build, un template est disponible dans Proxmox avec l'ID défini dans `template_vm_id`. Il peut ensuite être cloné par Terraform pour créer la VM pfSense.

```
Proxmox
└── Templates
    └── pfsense-2.7.2-template (ID: 200) ✅
```