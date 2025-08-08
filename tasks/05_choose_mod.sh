#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

# Nur interaktiv fragen, wenn NICHT NON_INTERACTIVE
if [ "${NON_INTERACTIVE:-0}" -eq 0 ]; then
  echo
  read -rp "Darkness Falls Mod installieren? (j/N): " ans
  INSTALL_DARKNESS_FALLS=0
  [[ "$ans" =~ ^[Jj] ]] && INSTALL_DARKNESS_FALLS=1

  if [ "$INSTALL_DARKNESS_FALLS" -eq 1 ] && [ -z "${DARKNESS_FALLS_URL:-}" ]; then
    echo "Bitte die Download-URL des Darkness Falls Mod (ZIP) angeben."
    read -rp "URL: " DARKNESS_FALLS_URL
  fi
else
  log "NON_INTERACTIVE=1: Mods werden nicht interaktiv abgefragt (INSTALL_DARKNESS_FALLS=${INSTALL_DARKNESS_FALLS:-0})."
fi

# Entscheidung persistieren (nicht die Haupt-config überschreiben)
cat > "${BASE_DIR}/config.local" <<EOF
INSTALL_DARKNESS_FALLS=${INSTALL_DARKNESS_FALLS:-0}
DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL:-}"
MODS_DIR="${MODS_DIR}"
EOF

ok "Mod-Entscheidung gespeichert -> ${BASE_DIR}/config.local"
