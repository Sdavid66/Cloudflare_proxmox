#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[Cloudflare Tunnel Installer]"

step() {
  echo -e "\n${LOG_PREFIX} ==> $1"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "${LOG_PREFIX} Ce script doit être exécuté en tant que root." >&2
    exit 1
  fi
}

install_dependencies() {
  step "Mise à jour des paquets système"
  apt-get update

  step "Installation des dépendances requises (curl, gnupg, lsb-release)"
  apt-get install -y curl gnupg lsb-release
}

add_cloudflare_repository() {
  step "Ajout de la clé GPG Cloudflare"
  curl -fsSL https://pkg.cloudflare.com/GPG.KEY | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg

  step "Ajout du dépôt Cloudflare à APT"
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ \$(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/cloudflare-main.list
}

install_cloudflared() {
  step "Actualisation des index APT avec le dépôt Cloudflare"
  apt-get update

  step "Installation du paquet cloudflared"
  apt-get install -y cloudflared
}

install_service() {
  if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
    step "Installation du service cloudflared avec le jeton fourni"
    cloudflared service install "${CLOUDFLARE_TUNNEL_TOKEN}"
  else
    step "Aucun jeton de tunnel fourni"
    cat <<'EOM'
${LOG_PREFIX} Vous pouvez fournir un jeton de tunnel via la variable d'environnement
${LOG_PREFIX} CLOUDFLARE_TUNNEL_TOKEN avant d'exécuter ce script pour configurer
${LOG_PREFIX} automatiquement le service cloudflared.
EOM
  fi
}

show_agent_information() {
  step "Informations sur l'agent Cloudflare"
  local ip_addresses
  if ip_addresses=$(hostname -I 2>/dev/null); then
    echo "${LOG_PREFIX} Adresse(s) IP détectée(s) : ${ip_addresses}"
  else
    echo "${LOG_PREFIX} Impossible de déterminer les adresses IP via hostname -I" >&2
  fi

  cat <<'EOM'
${LOG_PREFIX} Une fois le service installé, vous pouvez gérer le tunnel avec :
${LOG_PREFIX}   systemctl status cloudflared
${LOG_PREFIX}   journalctl -u cloudflared -f
EOM
}

main() {
  step "Initialisation de l'installation du tunnel Cloudflare"
  require_root
  install_dependencies
  add_cloudflare_repository
  install_cloudflared
  install_service
  show_agent_information
  step "Installation terminée"
}

main "$@"
