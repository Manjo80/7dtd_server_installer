# 7dtd-installer/tasks/90_summary.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

cat <<EOF

==================== FERTIG ====================
User:        ${APP_USER}
Install:     ${INSTALL_DIR}
SteamCMD:    ${STEAMCMD_BIN}
Branch:      $(tr -d '[:space:]' < "${INSTALL_DIR}/.branch" 2>/dev/null || echo public)
Service:     7d2d (falls systemd vorhanden)

Befehle:
  systemctl start|stop|status 7d2d
  systemctl restart 7d2d
  sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh update
  sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh status

Config:
  ${INSTALL_DIR}/serverconfig.xml (Telnet aktiv, Port 8081)
Ports (Host/Firewall):
  UDP 26900–26903, TCP 26900; Telnet nur intern (TCP 8081)
================================================
EOF
