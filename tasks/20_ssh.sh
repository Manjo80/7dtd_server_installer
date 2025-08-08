# 7dtd-installer/tasks/20_ssh.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

log "OpenSSH-Server installieren & aktivieren…"
ensure_pkgs openssh-server
systemctl enable --now ssh || true

if [ "${SSH_LIMIT_TO_USER}" -eq 1 ]; then
  # AllowUsers nur setzen, wenn noch nicht vorhanden
  if ! grep -qE "^\s*AllowUsers\b" /etc/ssh/sshd_config 2>/dev/null; then
    echo "AllowUsers ${APP_USER}" >> /etc/ssh/sshd_config
  elif ! grep -qE "^\s*AllowUsers\b.*\b${APP_USER}\b" /etc/ssh/sshd_config; then
    sed -i "s/^\s*AllowUsers.*/& ${APP_USER}/" /etc/ssh/sshd_config
  fi
  systemctl reload ssh || true
  ok "SSH erlaubt für User ${APP_USER} (AllowUsers)."
else
  ok "SSH ohne AllowUsers-Beschränkung."
fi
