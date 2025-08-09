#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

log "systemd-Service erstellen/aktivieren…"

# Unit ohne 'screen', Serverprozess läuft im Vordergrund
cat > /etc/systemd/system/7d2d.service <<EOF
[Unit]
Description=7 Days to Die Server
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=/bin/bash -lc './startserver.sh -configfile=serverconfig.xml -logfile 7d2d.log'
# Sanfter Stop: nutzt dein manage.sh (Telnet-Stop möglich, sonst quit)
ExecStop=${INSTALL_DIR}/bin/manage.sh stop
Restart=on-failure
RestartSec=5
# Empfohlenes Limit aus dem Log (sonst Warnung/Crash-Risiko)
LimitNOFILE=10240

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/7d2d.service
systemctl daemon-reload
systemctl enable --now 7d2d || true
systemctl status 7d2d --no-pager || true
ok "Service 7d2d aktiv."
