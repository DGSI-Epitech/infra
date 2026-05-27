# Agents & Skills Claude — DGSI Infra

Ce que Savinien a installé/créé pour ce projet. Tout ça tourne dans Claude Code.

---

## Agents (sous-IA spécialisées)

### `connectivity-checker`
Vérifie la connectivité SSH/Ansible sur tous les hosts. Lance `ansible ping`, teste les ProxyJumps via pfSense, et retourne qui répond et par quel chemin. Read-only, ne modifie rien.

Se déclenche automatiquement si tu mentionnes un problème réseau, ou à la demande :
```
"vérifie que tous les hosts sont joignables"
```

---

### `code-review-specialist`
Analyse les derniers changements git et classe les problèmes :
- 🔴 **CRITICAL** — bloque le déploiement
- 🟡 **WARNING** — à corriger bientôt
- 🔵 **SUGGESTION** — optionnel

Se déclenche **automatiquement** après chaque modification de code. Retourne un verdict `PASS / CONDITIONAL / BLOCK` avec des exemples avant/après.

À la demande :
```
"fais une revue de mes derniers changements"
```

---

### `code-simplifier` *(plugin)*
Simplifie et nettoie le code récemment modifié sans en changer le comportement. Réduit la complexité, améliore la lisibilité, supprime le code redondant.

```
"simplifie mon dernier playbook"
"lance le code-simplifier"
```

---

## Skills (commandes slash)

### `/ralph-loop` *(plugin)*
Lance une boucle autonome : Claude travaille sur une tâche, se relance tout seul à chaque fin d'itération jusqu'à ce que ce soit fait. Utile pour les tâches longues avec des critères de succès clairs (tests qui passent, déploiement complet, etc.).

```bash
/ralph-loop "Déploie le role base sur ops-vm et vérifie que tous les services tournent. Output <promise>DONE</promise> quand c'est bon." --completion-promise "DONE" --max-iterations 10
```

Arrêter la boucle en cours :
```
/cancel-ralph
```

> Mettre `--max-iterations` pour éviter une boucle infinie sur une tâche impossible.

---

### `/git-flow` *(à créer — voir Savinien)*
Gère tout le cycle Git : commit → rebase sur main → push → PR GitHub. À appeler quand tu veux envoyer tes modifs sans te prendre la tête avec git.

```
"fais une PR"
/git-flow
```
