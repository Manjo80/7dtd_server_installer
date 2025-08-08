# 7dtd-installer/tasks/00_packages.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

log "System aktualisieren & Basispackages installieren…"
ensure_pkgs sudo ca-certificates tzdata wget curl xz-utils tar nano screen telnet netcat-openbsd file procps unzip xmlstarlet 

# 32-bit Libs (benötigt von steamcmd/7dtd)
if apt-cache show lib32gcc-s1 >/dev/null 2>&1; then
  apt-get install -y lib32gcc-s1 || true
elif apt-cache show lib32gcc1 >/dev/null 2>&1; then
  apt-get install -y lib32gcc1 || true
fi
apt-get install -y lib32stdc++6 || true
ok "Packages fertig."
