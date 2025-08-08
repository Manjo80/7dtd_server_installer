#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

INSTALL_DARKNESS_FALLS="${INSTALL_DARKNESS_FALLS:-0}"
DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL:-}"

if [ "${NON_INTERACTIVE:-0}" -eq 0 ]; then
  echo
  echo "Darkness Falls installieren?"
  echo "  1) Nein"
  echo "  2) Ja – V5.1.0 für A21.2"
  echo "  3) Ja – V6 (für 7DTD v1.4 b8)"
  read -rp "Auswahl [1-3]: " ans
  case "$ans" in
    2)
      INSTALL_DARKNESS_FALLS=1
      # A21.2 (V5.1.0)
      DARKNESS_FALLS_URL="https://dev.azure.com/KhaineUK/292933d3-b55a-46b5-9fbc-f4e138ad47a4/_apis/git/repositories/0571597f-cf8c-42cd-8e35-7e799218cfe7/items?\$format=zip&api-version=5.0&download=true&path=%2F&resolveLfs=true&versionDescriptor%5BversionOptions%5D=0&versionDescriptor%5BversionType%5D=0&versionDescriptor%5Bversion%5D=master"
      ;;
    3)
      INSTALL_DARKNESS_FALLS=1
      # v1.4 b8 (V6)
      DARKNESS_FALLS_URL="https://dev.azure.com/KhaineUK/f8438d9f-d741-420b-9429-f0838ed77e7f/_apis/git/repositories/80d717da-eb1e-4211-b0c2-eae2d478e749/items?\$format=zip&api-version=5.0&download=true&path=%2F&resolveLfs=true&versionDescriptor%5BversionOptions%5D=0&versionDescriptor%5BversionType%5D=0&versionDescriptor%5Bversion%5D=main"
      ;;
    *) INSTALL_DARKNESS_FALLS=0 ;;
  esac
fi

# Persistieren, ohne config.env anzufassen
cat > "${BASE_DIR}/config.local" <<EOF
INSTALL_DARKNESS_FALLS=${INSTALL_DARKNESS_FALLS}
DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL}"
MODS_DIR="${MODS_DIR}"
EOF

[ "${INSTALL_DARKNESS_FALLS}" -eq 1 ] && \
  echo "[+] DF wird installiert aus: ${DARKNESS_FALLS_URL}" || \
  echo "[*] DF wird übersprungen."
