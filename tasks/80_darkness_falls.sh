#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

if [ "${INSTALL_DARKNESS_FALLS:-0}" -ne 1 ]; then
  log "Darkness Falls: übersprungen (INSTALL_DARKNESS_FALLS!=1)."
  exit 0
fi

if [ -z "${DARKNESS_FALLS_URL:-}" ]; then
  err "Darkness Falls: Keine DARKNESS_FALLS_URL gesetzt. Abbruch."
  exit 1
fi

log "Darkness Falls Mod wird installiert…"
install -d -m 755 "${MODS_DIR}"
chown -R "${APP_USER}:${APP_USER}" "$(dirname "${MODS_DIR}")"

tmp="$(mktemp)"
trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"; trap - RETURN' RETURN

# Server stoppen, falls läuft (best effort)
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop 7d2d || true
fi

# ZIP holen und entpacken als Spiel-User (falls Schreibrechte notwendig)
sudo -u "${APP_USER}" bash -lc "
  set -e
  cd '${MODS_DIR}'
  wget -O '${tmp##*/}.zip' '${DARKNESS_FALLS_URL}'
  unzip -o '${tmp##*/}.zip'
  rm -f '${tmp##*/}.zip'
"

# Hinweis: Manche DF-Pakete enthalten eine 'Mods' Struktur. Falls doppelte Ebene -> flachziehen
# (Optional – je nach Paketaufbau. Wenn nötig, hier verschieben.)

ok "Darkness Falls installiert in ${MODS_DIR}"

# Service ggf. wieder starten
if command -v systemctl >/dev/null 2>&1; then
  systemctl start 7d2d || true
fi
