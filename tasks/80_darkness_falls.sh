#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

if [ "${INSTALL_DARKNESS_FALLS:-0}" -ne 1 ]; then
  log "Darkness Falls: übersprungen."
  exit 0
fi
[ -n "${DARKNESS_FALLS_URL:-}" ] || { err "DF: Keine URL gesetzt."; exit 1; }

log "Darkness Falls herunterladen und installieren…"
install -d -m 755 "${MODS_DIR}"
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# Server stoppen (best effort), damit Dateien frei sind
if command -v systemctl >/dev/null 2>&1; then systemctl stop 7d2d || true; fi

# ZIP holen und entpacken
wget -O "${tmpdir}/df.zip" "${DARKNESS_FALLS_URL}"
unzip -q -o "${tmpdir}/df.zip" -d "${tmpdir}/df"

# a) Falls ZIP bereits 'Mods/' enthält -> Inhalt nach ${MODS_DIR} verschieben
if [ -d "${tmpdir}/df/Mods" ]; then
  rsync -a --delete "${tmpdir}/df/Mods/" "${MODS_DIR}/"
else
  # b) Ansonsten alles, was wie DF-Mods aussieht, in Mods/ kopieren
  # (Ordner mit ModInfo.xml)
  find "${tmpdir}/df" -type f -name ModInfo.xml -printf '%h\0' | \
    xargs -0 -I{} rsync -a "{}/" "${MODS_DIR}/$(basename "{}")/"
fi

chown -R "${APP_USER}:${APP_USER}" "${MODS_DIR}"
ok "Darkness Falls installiert in ${MODS_DIR}"

# Server wieder starten
if command -v systemctl >/dev/null 2>&1; then systemctl start 7d2d || true; fi
