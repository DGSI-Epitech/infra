# Decision on the project structure and organization

# 🛠️ Packer Build : pfSense Golden Image (Proxmox)

Ce projet permet de générer automatiquement un **Template Proxmox** pour pfSense 2.7.2 en utilisant l'approche **Infrastructure as Code (IaC)**.

## 🎯 Pourquoi utiliser Packer ici ?

L'installation manuelle d'un pare-feu est répétitive et sujette à l'erreur humaine (oubli d'une option, mauvais partitionnement). Packer nous permet de créer une **"Golden Image"** (Image d'Or) :
- **Standardisation** : Chaque instance pfSense partira exactement de la même base.
- **Vitesse** : Terraform pourra cloner ce template en quelques secondes au lieu de refaire une installation de 10 minutes.
- **Automatisation "Zero-Touch"** : Le robot Packer simule les frappes clavier à notre place pour l'installation.



---

## 🏗️ Ce que nous avons mis en place

### 1. Sécurité des accès
Nous utilisons un **Token API Proxmox** (`PVEAPIToken`) pour que Packer puisse piloter Proxmox sans utiliser le mot de passe `root`. 
*Les secrets sont stockés dans `pfsense-2.7.pkrvars.hcl` (exclu de Git via `.gitignore`).*

### 2. Le Workflow de Build
Le fichier `pfsense-2.7.pkr.hcl` définit la recette :
1. **Source** : Téléchargement et montage de l'ISO pfSense 2.7.2.
2. **Hardware** : Création d'une VM temporaire (2 vCPUs, 2Go RAM, VirtIO).
3. **Provisioning (Le "Fantôme")** : Une séquence de touches (`boot_command`) automatise l'installateur :
   - Acceptation des conditions.
   - Sélection du mode **UFS** (plus simple et fiable pour l'automatisation que ZFS).
   - Partitionnement automatique du disque de 10 Go.
   - Extinction propre via le Shell (`shutdown -p now`).
4. **Conversion** : Proxmox transforme la VM éteinte en **Template (ID 9001)**.

---

## 🚀 Comment lancer le build ?

Puisque nous utilisons l'exécutable local, voici les commandes à utiliser dans le terminal :

1. **Initialiser les plugins** (seulement la première fois) :
   ```bash
   ./packer.exe init .

   Lancer la création du template :

Bash
./packer.exe build -var-file="pfsense-2.7.pkrvars.hcl" .
Note : Ajoutez -force si vous voulez écraser un template existant portant le même ID.

📂 Architecture des fichiers
pfsense-2.7.pkr.hcl : Le code principal (définition de la VM et des touches clavier).

pfsense-2.7.pkrvars.hcl : Tes variables personnelles (URL Proxmox, Token, Node). Ne pas pusher sur GitHub.

packer.exe : L'exécutable Packer (version Windows).

Configuration automatique et déploiement via TerraformCette section détaille le processus de patching de la configuration et la mise en production de l'instance finale.1. Automatisation de la configuration (Injection Post-Install)Pour obtenir une installation Zero-Touch, le fichier de configuration système de pfSense est modifié avant le premier démarrage. Cette étape permet d'éviter l'assistant de configuration manuel et rend le pare-feu opérationnel immédiatement après son déploiement par Terraform.Pourquoi cette étape est nécessaire :Sans cette injection, pfSense interrompt le processus de démarrage pour demander l'assignation des interfaces et la configuration IP. L'automatisation garantit que :Les interfaces réseau VirtIO (vtnet0 et vtnet1) sont reconnues nativement.L'adresse IP du LAN est fixée sur 172.16.255.254.Le masque de sous-réseau est configuré en /28.Le serveur DHCP est pré-configuré pour la plage 172.16.255.241 - 172.16.255.253.Fonctionnement technique :À la fin de l'installation, Packer utilise le Shell de l'installateur pour exécuter les opérations suivantes :Montage de la partition système : mount /dev/vtbd0s1a /mnt.Création du répertoire cible : mkdir -p /mnt/cf/conf.Copie de la configuration d'usine : Le fichier config.xml est extrait du support d'installation.Patching via sed : Remplacement des valeurs par défaut par les paramètres réseau du projet.2. Déploiement de l'Infrastructure avec TerraformUne fois le Template (ID 9001) généré par Packer, Terraform est utilisé pour créer l'instance de production.Localisation du projet :Les commandes doivent être exécutées dans le répertoire suivant :Bashcd terraform/envs/onprem
Commandes de déploiement :CommandeObjectifterraform initInitialise le projet et télécharge les modules nécessaires.terraform plan -target=module.pfsenseVisualise les changements avant application.terraform apply -target=module.pfsenseClone le template et déploie la VM pfSense.terraform destroy -target=module.pfsenseSupprime l'instance du pare-feu.Résultat du déploiement :Une fois l'application terminée, pfSense démarre sur Proxmox avec la configuration suivante visible sur la console :WAN (vtnet0) : Configuration via DHCP.LAN (vtnet1) : IP statique 172.16.255.254/28.Le pare-feu est alors prêt à gérer le trafic réseau pour les autres ressources de l'infrastructure.