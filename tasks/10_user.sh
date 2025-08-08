# 7dtd-installer/tasks/10_user.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

log "User ${APP_USER} anlegen/prüfen…"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${APP_USER}" \
    || adduser --disabled-password --gecos "" --allow-bad-names "${APP_USER}"
  ok "User ${APP_USER} erstellt."
else
  ok "User ${APP_USER} existiert bereits."
fi

# Passwort setzen (interaktiv, außer NON_INTERACTIVE=1)
if [ "${NON_INTERACTIVE}" -eq 0 ]; then
  echo "Passwort für ${APP_USER} setzen:"
  while true; do
    read -rsp "Passwort: " p1; echo
    read -rsp "Passwort wiederholen: " p2; echo
    [ "$p1" = "$p2" ] || { err "Passwörter ungleich."; continue; }
    [ -n "$p1" ] || { err "Leeres Passwort nicht erlaubt."; continue; }
    echo "${APP_USER}:${p1}" | chpasswd
    ok "Passwort gesetzt."
    break
  done
else
  err "NON_INTERACTIVE=1: Passwort **nicht** gesetzt. Setze es manuell:  echo '${APP_USER}:NEUESPASS' | chpasswd"
fi
