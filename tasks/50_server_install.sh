# 7dtd-installer/tasks/50_server_install.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

log "Installiere 7DTD in ${INSTALL_DIR}…"
APPID="$(tr -d '[:space:]' < "${INSTALL_DIR}/.appid" 2>/dev/null || echo "${APPID}")"
BRANCH="$(tr -d '[:space:]' < "${INSTALL_DIR}/.branch" 2>/dev/null || echo public)"

cmd=(+force_install_dir "${INSTALL_DIR}" +login anonymous +app_update "${APPID}")
if [ -n "${BRANCH}" ] && [ "${BRANCH}" != "public" ]; then
  if [ -n "${BETAPASS:-}" ]; then
    cmd+=(-beta "${BRANCH}" -betapassword "${BETAPASS}")
  else
    cmd+=(-beta "${BRANCH}")
  fi
fi
cmd+=(validate +quit)

sudo -u "${APP_USER}" -H bash -lc "
  cd '${STEAMCMD_DIR}'
  bash ./steamcmd.sh ${cmd[*]}
"
ok "Serverfiles installiert."
