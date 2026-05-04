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


# 🌍 Interconnexion Multi-Sites : Tunnel VPN pfSense avec OpenVPN & Ansible

Ce document explique l'architecture de notre réseau inter-sites, le choix des technologies (OpenVPN) et l'intérêt de notre approche d'automatisation via Ansible.

---

## 🏗️ 1. Pourquoi un tunnel VPN entre les deux sites Proxmox ?

Nos deux serveurs Proxmox agissent comme deux datacenters distincts. Par défaut, les machines virtuelles (VMs) hébergées sur le Site 1 ne peuvent pas communiquer avec les VMs du Site 2, car elles sont isolées derrière leurs pare-feux pfSense respectifs et séparées par Internet.

Mettre en place un tunnel VPN **Site-à-Site (Site-to-Site)** entre les deux routeurs pfSense permet de :
* **Créer un réseau global unifié :** Les VMs du Site 1 et du Site 2 peuvent communiquer entre elles via leurs adresses IP privées (LAN), comme si elles étaient branchées sur le même switch physique.
* **Sécuriser les échanges :** Tout le trafic transitant entre les deux Proxmox via Internet est chiffré. Même en cas d'interception, les données sont illisibles.
* **Centraliser les services :** Cela permet, par exemple, à un serveur Vault ou à une base de données sur le Site 1 d'être consommé de manière sécurisée par des applications hébergées sur le Site 2.

---

## 🔒 2. Pourquoi choisir OpenVPN ?

Bien que ce choix soit imposé par les contraintes du projet, OpenVPN est un standard de l'industrie pour d'excellentes raisons :

* **Maturité et Fiabilité :** C'est une solution open-source éprouvée depuis plus de 20 ans, auditée massivement par la communauté cybersécurité.
* **Sécurité robuste (SSL/TLS) :** Contrairement à d'autres protocoles plus anciens (comme PPTP), OpenVPN repose sur OpenSSL. Il utilise des certificats pour l'authentification et des algorithmes de chiffrement forts (comme AES-256) pour les données.
* **Flexibilité réseau :** Il passe très facilement les pare-feux et les NAT, car il peut encapsuler son trafic dans un simple flux UDP ou TCP sur un port personnalisable (généralement 1194).
* **Intégration native dans pfSense :** pfSense gère OpenVPN de manière excellente, avec des interfaces dédiées pour la gestion des certificats (PKI), le routage et les règles de pare-feu.

---

## ⚙️ 3. Comment fonctionne OpenVPN (Sous le capot) ?

Pour faire simple, OpenVPN crée une "tuyauterie virtuelle" sécurisée au milieu d'Internet. Voici comment il opère :

1. **L'Architecture Peer-to-Peer / Client-Serveur :** Un des pfSense est configuré en tant que "Serveur" (celui qui écoute), et l'autre en tant que "Client" (celui qui initie la connexion).
2. **L'Authentification par Certificats (PKI) :** Avant de se parler, les deux pfSense vérifient leur identité à l'aide de certificats cryptographiques générés par une Autorité de Certification (CA) commune. Si le certificat n'est pas signé par la bonne CA, la connexion est coupée net.
3. **L'Interface Virtuelle (TUN) :** OpenVPN crée une carte réseau virtuelle (interface `tun`) sur chaque pfSense. Quand le routeur veut envoyer un paquet à l'autre site, il l'envoie dans cette interface.
4. **L'Encapsulation et le Chiffrement :** OpenVPN prend ce paquet privé, le chiffre avec une clé symétrique, le met dans une "boîte" (encapsulation), et l'envoie sur Internet de manière anonyme. À la réception, l'autre pfSense ouvre la boîte, déchiffre le paquet et le livre au réseau local.

---

## 🤖 4. La magie d'Ansible : Pourquoi tout faire par le code ?

Configurer un VPN Site-à-Site sur pfSense implique normalement des dizaines de clics dans l'interface web : créer la CA, générer les certificats, configurer le serveur VPN, configurer le client, ajouter les règles de pare-feu WAN et OpenVPN, et configurer le routage.

Le faire via **Ansible (Infrastructure as Code)** change totalement la donne :

* **Zéro erreur humaine :** Fini l'oubli d'une case à cocher ou l'erreur de frappe dans un sous-réseau. Le code applique exactement la configuration définie.
* **Reproductibilité totale :** Si un pfSense crashe ou si l'on doit recréer l'infrastructure (comme on le fait avec Terraform et nos scripts de déploiement), Ansible remonte le VPN en quelques secondes, sans aucune intervention manuelle.
* **Documentation vivante :** Le code Ansible (`playbooks` et `roles`) sert de documentation exacte de l'état de notre réseau. Tout membre de l'équipe peut lire le code et comprendre le paramétrage du VPN (ports, algorithmes, sous-réseaux).
* **Idempotence :** Ansible ne fait les modifications que si elles sont nécessaires. Si on relance le script, il vérifiera que le VPN est bien là et ne cassera rien.



# 🔐 PKI Interne : Autorité de Certification (CA) pfSense & Ansible

Ce document explique le rôle de notre Autorité de Certification (CA) interne hébergée sur pfSense, l'importance du chiffrement TLS (HTTPS) pour nos services, et l'intérêt de gérer cette infrastructure cryptographique par le code avec Ansible.

---

## 🏛️ 1. Qu'est-ce qu'une Autorité de Certification (CA) Interne ?

Dans le monde du web public, on utilise des entités reconnues (comme Let's Encrypt ou DigiCert) pour certifier que "google.com" est bien le vrai site de Google. 

Dans une infrastructure privée ou de laboratoire (comme notre réseau Proxmox/pfSense), nous n'avons pas de noms de domaine publics. Nous devons donc **créer notre propre "Préfecture" capable de délivrer des "Passeports" (les certificats) à nos propres serveurs**. 

C'est exactement le rôle de notre **CA pfSense** :
* Elle agit comme le tiers de confiance absolu pour tout notre réseau interne.
* Elle forge et signe cryptographiquement les certificats de nos machines (comme notre serveur Vault).
* Une fois que le certificat public de cette CA est installé sur nos postes de travail ou nos autres VMs, tous les services signés par elle sont automatiquement reconnus comme légitimes et sécurisés.

---

## 🛡️ 2. Pourquoi délivrer du TLS (HTTPS) pour nos services internes ?

On pourrait se dire : *"C'est un réseau interne privé (LAN), pourquoi s'embêter à chiffrer en HTTPS ?"* 

Dans les standards modernes (et particulièrement dans les architectures Cloud et Zero Trust), le réseau interne n'est plus considéré comme 100% sûr. Le TLS (Transport Layer Security) apporte trois garanties fondamentales :

1. **Confidentialité (Chiffrement en transit) :** Quand on communique avec notre gestionnaire de secrets (Vault) ou une application web, les mots de passe et les tokens transitent sur le réseau. Sans TLS (en HTTP simple), n'importe quelle machine compromise sur le même réseau (via du *sniffing*) pourrait lire ces secrets en clair. Le TLS rend ces données totalement indéchiffrables.
2. **Authentification (Anti-Usurpation) :** Le TLS garantit que la VM à l'adresse `172.16.0.244` est *réellement* notre serveur Vault, et non un pirate qui aurait usurpé l'adresse IP (attaque ARP Spoofing) pour voler nos identifiants.
3. **Intégrité :** Le TLS s'assure qu'aucun paquet réseau n'a été altéré ou modifié en cours de route.

---

## 🧠 3. Pourquoi héberger la CA sur pfSense ?

Héberger la clé maître de notre infrastructure sur le routeur est un choix stratégique :
* **Outil natif robuste :** pfSense intègre un gestionnaire de PKI (Public Key Infrastructure) d'entreprise, extrêmement fiable, basé sur FreeBSD et OpenSSL.
* **Séparation des rôles :** La CA ne doit pas se trouver sur le même serveur que les applications (comme Vault ou les web services). Si une VM applicative est compromise, la CA (et donc la confiance de tout le réseau) reste protégée derrière le pare-feu.
* **Centralisation :** pfSense génère les certificats pour le VPN (OpenVPN), pour l'accès à sa propre interface web, et pour les VMs internes. Tout est géré au même endroit.

---

## 🤖 4. La plus-value d'Ansible pour la PKI (Infrastructure as Code)

Gérer des certificats manuellement est souvent source d'erreurs, d'oublis de renouvellement, ou de problèmes de copier-coller. L'automatisation via Ansible transforme cette corvée en un processus fiable :

* **Génération déterministe :** Le playbook Ansible définit exactement les caractéristiques de la CA (algorithme RSA 4096 bits, SHA-256, validité de 10 ans, informations de l'organisation). Il n'y a pas d'erreur humaine possible.
* **Extraction et distribution dynamiques :** L'énorme avantage d'Ansible est sa capacité à parler à pfSense pour créer la CA, extraire instantanément le certificat public généré, et l'injecter directement dans nos futures machines (comme Vault) au sein du même pipeline de déploiement.
* **Sécurité des manipulations :** Les certificats et les clés ne traînent pas sur les postes des développeurs, tout se fait de machine à machine (de Debian vers pfSense via SSH sécurisé).