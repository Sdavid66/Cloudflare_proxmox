#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="noninteractive"

LOG_PREFIX="[Proxmox Cloudflared Installer]"

# Paramètres configurables via variables d'environnement
VM_ID="${VM_ID:-9000}"
VM_NAME="${VM_NAME:-cloudflared-tunnel}"
VM_MEMORY="${VM_MEMORY:-1024}"
VM_CORES="${VM_CORES:-1}"
VM_BRIDGE="${VM_BRIDGE:-vmbr0}"
VM_STORAGE="${VM_STORAGE:-local-lvm}"
VM_DISK_RESIZE="${VM_DISK_RESIZE:-10G}"
CI_USER="${CI_USER:-cloudflared}"
CI_PASSWORD="${CI_PASSWORD:-Cloudflare123!}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
CLOUD_IMAGE_URL="${CLOUD_IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"
CLOUD_IMAGE_NAME="${CLOUD_IMAGE_NAME:-debian-12-genericcloud-amd64.qcow2}"
SNIPPET_STORAGE="${SNIPPET_STORAGE:-local}"
SNIPPET_NAME="${SNIPPET_NAME:-${VM_NAME}-cloudinit.yaml}"
WAIT_FOR_AGENT_TIMEOUT="${WAIT_FOR_AGENT_TIMEOUT:-600}"
WAIT_FOR_AGENT_INTERVAL="${WAIT_FOR_AGENT_INTERVAL:-10}"

IMAGE_DEST="/var/lib/vz/template/iso/${CLOUD_IMAGE_NAME}"
SNIPPET_PATH="/var/lib/vz/snippets/${SNIPPET_NAME}"

step() {
  echo -e "\n${LOG_PREFIX} ==> $1"
}

info() {
  echo "${LOG_PREFIX} $1"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "${LOG_PREFIX} Ce script doit être exécuté en tant que root." >&2
    exit 1
  fi
}

require_commands() {
  local missing=()
  for cmd in qm pvesm curl wget openssl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "${LOG_PREFIX} Les commandes suivantes sont requises mais absentes : ${missing[*]}" >&2
    echo "${LOG_PREFIX} Installez-les puis relancez le script." >&2
    exit 1
  fi
}

ensure_storage_exists() {
  local storage="$1"
  if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx "${storage}"; then
    echo "${LOG_PREFIX} Le stockage '${storage}' est introuvable." >&2
    exit 1
  fi
}

ensure_snippet_support() {
  step "Vérification du support des snippets Cloud-Init"
  ensure_storage_exists "${SNIPPET_STORAGE}"

  local storage_cfg="/etc/pve/storage.cfg"
  if [[ ! -f "${storage_cfg}" ]]; then
    echo "${LOG_PREFIX} Fichier ${storage_cfg} introuvable." >&2
    exit 1
  fi

  if ! awk -v storage="${SNIPPET_STORAGE}" '
      $0 ~ "^"storage":" {in_block=1; next}
      in_block && $1=="content" {if ($0 ~ /snippets/) found=1}
      in_block && /^$/ {in_block=0}
      END {exit found?0:1}
    ' "${storage_cfg}"; then
    info "Activation du contenu 'snippets' sur le stockage ${SNIPPET_STORAGE}"
    local existing
    existing=$(awk -v storage="${SNIPPET_STORAGE}" '
      $0 ~ "^"storage":" {in_block=1; next}
      in_block && $1=="content" {print $2; exit}
      in_block && /^$/ {exit}
    ' "${storage_cfg}")
    if [[ -n "${existing}" ]]; then
      pvesm set "${SNIPPET_STORAGE}" --content "${existing},snippets"
    else
      pvesm set "${SNIPPET_STORAGE}" --content snippets
    fi
  fi

  install -d -m 0755 /var/lib/vz/snippets
}

check_vmid_availability() {
  if qm list | awk 'NR>1 {print $1}' | grep -qx "${VM_ID}"; then
    echo "${LOG_PREFIX} Le VMID ${VM_ID} existe déjà. Utilisez une autre valeur ou supprimez la VM." >&2
    exit 1
  fi
}

download_cloud_image() {
  step "Téléchargement de l'image Debian Cloud (${CLOUD_IMAGE_NAME})"
  install -d -m 0755 /var/lib/vz/template/iso
  if [[ -f "${IMAGE_DEST}" ]]; then
    info "Image déjà présente, téléchargement ignoré."
  else
    wget -O "${IMAGE_DEST}" "${CLOUD_IMAGE_URL}"
  fi
}

create_vm_definition() {
  step "Création de la VM ${VM_NAME} (ID ${VM_ID})"
  qm create "${VM_ID}" \
    --name "${VM_NAME}" \
    --memory "${VM_MEMORY}" \
    --cores "${VM_CORES}" \
    --net0 "virtio,bridge=${VM_BRIDGE}" \
    --agent enabled=1,fstrim_cloned_disks=1 \
    --ostype l26 \
    --scsihw virtio-scsi-pci \
    --boot c \
    --bootdisk scsi0

  qm importdisk "${VM_ID}" "${IMAGE_DEST}" "${VM_STORAGE}" --format qcow2
  qm set "${VM_ID}" --scsi0 "${VM_STORAGE}:vm-${VM_ID}-disk-0"
  qm set "${VM_ID}" --ide2 "${VM_STORAGE}:cloudinit"
  qm set "${VM_ID}" --serial0 socket --vga serial0
  qm set "${VM_ID}" --ipconfig0 ip=dhcp

  if [[ -n "${VM_DISK_RESIZE}" ]]; then
    step "Redimensionnement du disque système (${VM_DISK_RESIZE})"
    qm resize "${VM_ID}" scsi0 "${VM_DISK_RESIZE}"
  fi
}

generate_password_hash() {
  step "Génération du mot de passe Cloud-Init"
  PASSWORD_HASH=$(openssl passwd -6 "${CI_PASSWORD}")
}

create_cloud_init_snippet() {
  step "Création du snippet Cloud-Init"
  cat <<EOF2 > "${SNIPPET_PATH}"
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
users:
  - name: ${CI_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: ${PASSWORD_HASH}
EOF2

  if [[ -n "${SSH_PUBLIC_KEY}" ]]; then
    cat <<EOF2 >> "${SNIPPET_PATH}"
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}
EOF2
  fi

  cat <<'EOF2' >> "${SNIPPET_PATH}"

package_update: true
package_upgrade: true
packages:
  - curl
  - gnupg
  - lsb-release
  - ca-certificates
  - qemu-guest-agent
write_files:
  - path: /usr/local/bin/install-cloudflared.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y --no-install-recommends curl gnupg lsb-release ca-certificates
      install -d -m 0755 /usr/share/keyrings
      curl -fsSL https://pkg.cloudflare.com/GPG.KEY | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-main.list
      apt-get update
      apt-get install -y --no-install-recommends cloudflared
EOF2

  if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]]; then
    cat <<EOF2 >> "${SNIPPET_PATH}"
runcmd:
  - [ bash, /usr/local/bin/install-cloudflared.sh ]
  - [ cloudflared, service, install, "${CLOUDFLARE_TUNNEL_TOKEN}" ]
  - [ systemctl, restart, cloudflared ]
EOF2
  else
    cat <<'EOF2' >> "${SNIPPET_PATH}"
runcmd:
  - [ bash, /usr/local/bin/install-cloudflared.sh ]
EOF2
  fi

  cat <<'EOF2' >> "${SNIPPET_PATH}"
final_message: "Installation de cloudflared terminée."
EOF2

  qm set "${VM_ID}" --cicustom "user=${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}" --ciuser "${CI_USER}" --cipassword "${CI_PASSWORD}"
}

start_vm() {
  step "Démarrage de la VM ${VM_NAME}"
  qm start "${VM_ID}"
}

fetch_guest_ip() {
  step "Attente de l'agent QEMU pour récupérer l'adresse IP"
  local elapsed=0
  while (( elapsed < WAIT_FOR_AGENT_TIMEOUT )); do
    if ip_json=$(qm guest cmd "${VM_ID}" network-get-interfaces 2>/dev/null); then
      local ip
      ip=$(printf '%s' "${ip_json}" | python3 - <<'PY'
import json, sys
interfaces = json.load(sys.stdin)
for interface in interfaces:
    for addr in interface.get("ip-addresses", []):
        if addr.get("ip-address-type") == "ipv4" and not addr.get("ip-address", "").startswith("127."):
            print(addr["ip-address"])
            raise SystemExit
print("")
PY
)
      if [[ -n "${ip}" ]]; then
        echo "${ip}"
        return 0
      fi
    fi
    sleep "${WAIT_FOR_AGENT_INTERVAL}"
    elapsed=$(( elapsed + WAIT_FOR_AGENT_INTERVAL ))
  done
  return 1
}

show_completion_message() {
  local vm_ip="$1"
  step "VM ${VM_NAME} créée avec succès"
  if [[ -n "${vm_ip}" ]]; then
    info "Adresse IP détectée via l'agent invité : ${vm_ip}"
    info "Vous pouvez vous connecter avec : ssh ${CI_USER}@${vm_ip}"
  else
    info "Impossible de récupérer automatiquement l'adresse IP. Consultez l'interface Proxmox ou utilisez 'qm guest cmd ${VM_ID} network-get-interfaces' plus tard."
  fi
  info "Le mot de passe utilisateur Cloud-Init est : ${CI_PASSWORD}"
  if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]]; then
    info "Le service cloudflared a été installé avec le jeton fourni."
  else
    info "Connectez-vous à la VM pour terminer la configuration du tunnel (cloudflared tunnel login/service install)."
  fi
}

main() {
  step "Initialisation de l'installation du tunnel Cloudflare sur une VM dédiée"
  require_root
  require_commands
  ensure_snippet_support
  ensure_storage_exists "${VM_STORAGE}"
  check_vmid_availability
  download_cloud_image
  create_vm_definition
  generate_password_hash
  create_cloud_init_snippet
  start_vm
  local vm_ip=""
  if vm_ip=$(fetch_guest_ip); then
    show_completion_message "${vm_ip}"
  else
    show_completion_message ""
  fi
  step "Procédure terminée"
}

main "$@"
