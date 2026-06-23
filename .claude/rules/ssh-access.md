# Règles d'accès SSH

## Ce qui marche
- SSH direct sur pfSense-OP : `ssh admin@192.168.255.254`
- SSH direct sur pfSense-Cloud : `ssh admin@5.196.50.52`

## Ce qui est bloqué
- Shell PVE1 / PVE2 : **impossible**, pas d'accès console ni root SSH
- Le token Proxmox API `root@pam!packer` retourne 401 sur les endpoints node — il est scope-limité à Packer

## Alternative pour ops-vm / services-vm
Si le ProxyJump via `root@PVE1` échoue (clé non autorisée), tenter via pfSense comme jump host :
```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253   # ops-vm
ssh -J admin@192.168.255.254 dgsi-cloud@172.16.0.241  # services-vm
```
Si pfSense refuse le forwarding TCP, la seule solution est que l'utilisateur ajoute la clé dans PVE1 via l'UI web Proxmox (port 8006 → nœud vm3 → Shell).

## Ne jamais demander
- D'ouvrir une console physique Proxmox
- D'utiliser `virsh`, `qm terminal` ou tout accès console VM depuis PVE
