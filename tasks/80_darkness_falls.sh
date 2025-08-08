#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

if [ "${INSTALL_DARKNESS_FALLS}" -eq 1 ]; then
  log "Darkness Falls Mod wird installiert..."
  # Beispiel: Mod per wget + unzip installieren (Pfad anpassen)
  MOD_URL="https://example.com/DarknessFalls.zip"
  sudo -u "${APP_USER}" bash -lc "
    cd '${INSTALL_DIR}/Mods'
    wget -qO DarknessFalls.zip \"${MOD_URL}\"
    unzip -o DarknessFalls.zip -d DarknessFalls
    rm DarknessFalls.zip
  "
  ok "Darkness Falls installiert."
else
  log "Darkness Falls wird übersprungen."
fi
