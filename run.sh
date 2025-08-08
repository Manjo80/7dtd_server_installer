# 7dtd-installer/run.sh
#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"
require_root

# Reihenfolge der Tasks
TASKS=(
  "00_packages.sh"
  "10_user.sh"
  "20_ssh.sh"
  "30_steamcmd.sh"
  "40_choose_version.sh"
  "50_server_install.sh"
  "60_scripts.sh"
  "70_systemd.sh"
  "90_summary.sh"
)

for t in "${TASKS[@]}"; do
  log "Task: ${t}"
  bash "${BASE_DIR}/tasks/${t}"
done
ok "Alle Tasks erledigt."
