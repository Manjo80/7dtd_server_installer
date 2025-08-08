# 7dtd-installer/tasks/70_systemd.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

log "systemd-Service erstellen/aktivieren (falls verfügbar)…"
if command -v systemctl >/dev/null 2>&1; then
  cat > /etc/systemd/system/7d2d.service <<EOF
[Unit]
Description=7 Days to Die Server
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/manage.sh start
ExecStop=${INSTALL_DIR}/bin/manage.sh stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 /etc/systemd/system/7d2d.service
  systemctl daemon-reload
  systemctl enable --now 7d2d || true
  systemctl status 7d2d --no-pager || true
  ok "Service 7d2d aktiv."
else
  err "Kein systemd im Container. Manuell starten: sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh start"
fi
