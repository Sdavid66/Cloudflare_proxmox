# Création automatique d'une VM Cloudflared sur Proxmox

Ce dépôt fournit un script shell capable de créer automatiquement une machine virtuelle Debian prête à héberger un tunnel Cloudflare depuis l'hyperviseur Proxmox. Le script prépare la VM, installe `cloudflared`, active l'agent invité QEMU et peut, si vous le souhaitez, enregistrer immédiatement le service Cloudflare à l'aide d'un jeton.

## Script d'installation

Le script principal se trouve dans `scripts/install_cloudflare_tunnel.sh`.

### Ce que fait le script

1. Vérifie la présence des outils Proxmox nécessaires (`qm`, `pvesm`, etc.).
2. Télécharge l'image cloud Debian 12 officielle si elle n'est pas encore disponible sur l'hôte.
3. Crée une VM dédiée avec Cloud-Init, configure le disque, la mémoire, le réseau et active l'agent invité pour récupérer l'adresse IP automatiquement.
4. Génère un snippet Cloud-Init qui installe `cloudflared`, `qemu-guest-agent` et configure un utilisateur administrateur.
5. Démarre la VM, attend que l'agent invité soit disponible puis affiche l'adresse IP détectée ainsi que les prochaines étapes.

### Pré-requis

- Exécuter le script depuis le shell du nœud Proxmox en tant que `root` (ou via `sudo`).
- Disposer d'un stockage Proxmox acceptant les snippets Cloud-Init (le script peut activer le type de contenu `snippets` sur le stockage local si besoin).
- Optionnel : fournir un jeton Cloudflare via `CLOUDFLARE_TUNNEL_TOKEN` pour enregistrer immédiatement le tunnel.

### Variables d'environnement disponibles

| Variable | Description | Valeur par défaut |
| --- | --- | --- |
| `VM_ID` | Identifiant numérique de la VM créée | `9000` |
| `VM_NAME` | Nom de la VM | `cloudflared-tunnel` |
| `VM_MEMORY` | Mémoire RAM en MiB | `1024` |
| `VM_CORES` | Nombre de vCPU | `1` |
| `VM_BRIDGE` | Pont réseau Proxmox utilisé | `vmbr0` |
| `VM_STORAGE` | Stockage cible pour le disque de la VM | `local-lvm` |
| `VM_DISK_RESIZE` | Taille finale du disque système (ex : `10G`) | `10G` |
| `CI_USER` | Nom de l'utilisateur créé via Cloud-Init | `cloudflared` |
| `CI_PASSWORD` | Mot de passe de l'utilisateur Cloud-Init | `Cloudflare123!` |
| `SSH_PUBLIC_KEY` | Clé publique SSH à ajouter à l'utilisateur | *(vide)* |
| `CLOUDFLARE_TUNNEL_TOKEN` | Jeton Cloudflare pour installer automatiquement le service | *(vide)* |
| `CLOUD_IMAGE_URL` | URL de l'image Debian cloud à utiliser | Debian 12 (Bookworm) |
| `CLOUD_IMAGE_NAME` | Nom du fichier image stocké localement | `debian-12-genericcloud-amd64.qcow2` |
| `SNIPPET_STORAGE` | Stockage contenant les snippets Cloud-Init (un stockage de type dossier est recommandé) | `local` |
| `SNIPPET_NAME` | Nom du snippet Cloud-Init généré | `<VM_NAME>-cloudinit.yaml` |

### Exécution locale

```bash
sudo ./scripts/install_cloudflare_tunnel.sh
```

### Exécution distante (depuis GitHub)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sdavid66/omv-proxmox-swiss/main/scripts/install_cloudflare_tunnel.sh)"
```

### Exemple avec un jeton de tunnel

```bash
sudo CLOUDFLARE_TUNNEL_TOKEN="<votre_jeton>" \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/sdavid66/omv-proxmox-swiss/main/scripts/install_cloudflare_tunnel.sh)"
```

Après l'exécution, la console Proxmox affichera les étapes effectuées ainsi que l'adresse IP détectée pour la nouvelle VM (grâce à l'agent QEMU installé automatiquement). Vous pourrez ensuite vous connecter à la VM et gérer le service `cloudflared` comme d'habitude (`systemctl status cloudflared`, `journalctl -u cloudflared -f`, etc.).
