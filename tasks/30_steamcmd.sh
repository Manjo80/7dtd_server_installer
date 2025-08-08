# 7dtd-installer/tasks/30_steamcmd.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

log "SteamCMD idempotent installieren…"
mkdir -p "${STEAMCMD_DIR}"
cd "${STEAMCMD_DIR}"

if [ ! -f steamcmd.sh ] && [ ! -f steamcmd_linux.tar.gz ]; then
  wget -q http://media.steampowered.com/installer/steamcmd_linux.tar.gz
fi
if [ ! -f steamcmd.sh ] && [ -f steamcmd_linux.tar.gz ]; then
  tar xzf steamcmd_linux.tar.gz
fi
# Wrapper (optional Bequemlichkeit)
if [ ! -x /usr/games/steamcmd ]; then
  cat >/usr/games/steamcmd <<'EOF'
#!/usr/bin/env bash
cd /opt/steamcmd
exec bash ./steamcmd.sh "$@"
EOF
  chmod +x /usr/games/steamcmd
fi

[ -d "${STEAMCMD_DIR}/linux32" ] || { [ -f steamcmd_linux.tar.gz ] && tar xzf steamcmd_linux.tar.gz; }
ok "SteamCMD: ${STEAMCMD_BIN}"
