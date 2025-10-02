# Installation du tunnel Cloudflare sur Proxmox

Ce dépôt contient un script shell permettant d'installer rapidement le tunnel Cloudflare sur une machine virtuelle Proxmox.

## Script d'installation

Le script principal se trouve dans `scripts/install_cloudflare_tunnel.sh`.

### Pré-requis
- Exécuter le script en tant que `root` (ou avec `sudo`).
- Optionnel : définir la variable d'environnement `CLOUDFLARE_TUNNEL_TOKEN` avec le jeton généré depuis le tableau de bord Cloudflare pour installer automatiquement le service.

### Utilisation
```bash
sudo ./scripts/install_cloudflare_tunnel.sh
```

Vous pouvez également exécuter le script à distance sans le télécharger au préalable :

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sdavid66/omv-proxmox-swiss/main/scripts/install_cloudflare_tunnel.sh)"
```

Pour installer directement le service `cloudflared` avec votre tunnel :

```bash
export CLOUDFLARE_TUNNEL_TOKEN="<votre_jeton>"
sudo ./scripts/install_cloudflare_tunnel.sh
```

Ou à distance en une seule commande :

```bash
sudo CLOUDFLARE_TUNNEL_TOKEN="<votre_jeton>" bash -c "$(curl -fsSL https://raw.githubusercontent.com/sdavid66/omv-proxmox-swiss/main/scripts/install_cloudflare_tunnel.sh)"
```

Le script affiche chaque étape de l'installation, installe les dépendances requises, ajoute le dépôt officiel Cloudflare, installe `cloudflared` puis affiche l'adresse IP locale de la machine pour identifier l'agent.
