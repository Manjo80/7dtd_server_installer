#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${BASE_DIR}/config.env"
# <- zusätzliche lokale Overrides (vom choose-Task geschrieben)
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"

source "${BASE_DIR}/lib/common.sh"
require_root

chmod +x "${BASE_DIR}/lib/common.sh" || true
chmod +x "${BASE_DIR}/tasks/"*.sh || true

TASKS=(
  "00_packages.sh"
  "10_user.sh"
  "20_ssh.sh"
  "30_steamcmd.sh"
  "05_choose_mod.sh" 
  "40_choose_version.sh"  
  "50_server_install.sh"
  "45_configure_server.sh"
  "60_scripts.sh"
  "80_darkness_falls.sh"   
  "70_systemd.sh"
  "90_summary.sh"
)

for t in "${TASKS[@]}"; do
  log "Task: ${t}"
  bash "${BASE_DIR}/tasks/${t}"
done

ok "Alle Tasks erledigt."
