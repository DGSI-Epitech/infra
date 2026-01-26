## 🚀 Terraform – Commandes standardisées

Afin de garantir une expérience **identique sur Windows, macOS et Linux**, ce projet utilise un `package.json` comme **point d’entrée unique** pour exécuter les commandes Terraform.
Node.js est utilisé uniquement comme **orchestrateur de commandes**, Terraform restant l’outil principal d’Infrastructure as Code.

---

### 📦 Prérequis

* Node.js ≥ 18
* Git
* Accès réseau aux API Proxmox (DEV / PROD selon le contexte)

> Terraform n’a pas besoin d’être installé manuellement : une commande dédiée s’en charge automatiquement.

---

## ⚙️ Installation de Terraform

```bash
npm run setup
```

Cette commande :

* détecte le système d’exploitation (Windows / macOS / Linux)
* installe Terraform via le gestionnaire de paquets approprié :

    * **Windows** : Chocolatey ou Winget
    * **macOS** : Homebrew
    * **Linux** : APT (HashiCorp officiel)
* vérifie la version installée

👉 Cette étape est requise uniquement **la première fois**.

---

## 🧪 Vérifications locales (avant un push)

```bash
npm run tf:check
```

Cette commande exécute, dans l’ordre :

1. le formatage du code Terraform
2. la validation de la configuration
3. un `terraform plan` sur l’environnement **on-prem (DEV)**

Elle permet de détecter les erreurs de syntaxe ou de configuration **avant toute mise en production**.

---

## 🏗️ Environnement DEV (site on-prem)

Les commandes suivantes sont utilisées **uniquement en développement** :

```bash
npm run tf:init:dev
npm run tf:plan:dev
npm run tf:apply:dev
```

* `init` : initialise Terraform et le backend de state
* `plan` : affiche les changements à venir
* `apply` : applique les changements sur l’environnement DEV

---

## 🔒 Environnement PROD (site remote)

Les commandes de production sont volontairement **restreintes** :

```bash
npm run tf:init:prod
npm run tf:plan:prod
```

L’application des changements en production (`terraform apply`) est **désactivée en local** et doit obligatoirement passer par la **CI/CD**, afin de respecter l’approche GitOps et éviter toute action manuelle non contrôlée.

---

## 🛡️ Sécurité et bonnes pratiques

* Aucune information sensible (tokens, mots de passe) n’est stockée dans le dépôt
* Les credentials sont injectés via :

    * des variables d’environnement
    * ou les secrets de la CI/CD
* Chaque site Proxmox dispose de son propre state Terraform
* Toute modification passe par une Pull Request avec revue
