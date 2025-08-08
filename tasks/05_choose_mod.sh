#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

# Defaults (werden ggf. überschrieben)
INSTALL_DARKNESS_FALLS="${INSTALL_DARKNESS_FALLS:-0}"
DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL:-}"
PREFERRED_BRANCH_NAME="${PREFERRED_BRANCH_NAME:-}"   # wird von 40_choose_version.sh bevorzugt

if [ "${NON_INTERACTIVE:-0}" -eq 0 ]; then
  echo
  echo "Darkness Falls installieren?"
  echo "  1) Nein"
  echo "  2) Ja – V5.1.0 (für 7DTD Alpha 21.2)"
  echo "  3) Ja – V6 (für 7DTD 1.0 / 1.4 b8)"
  read -rp "Auswahl [1-3]: " ans

  case "$ans" in
    2)
      INSTALL_DARKNESS_FALLS=1
      # Achtung: Link ggf. pflegen, falls sich die Quelle ändert.
      # (Offiziell verlinken die Buttons auf ZIP-Archive der DF-Repos.)
      DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL:-https://dev.azure.com/KhaineUK/292933d3-b55a-46b5-9fbc-f4e138ad47a4/_apis/git/repositories/0571597f-cf8c-42cd-8e35-7e799218cfe7/items?path=/&versionDescriptor%5BversionOptions%5D=0&versionDescriptor%5BversionType%5D=0&versionDescriptor%5Bversion%5D=master&resolveLfs=true&%24format=zip&api-version=5.0&download=true}"
      # Für DF V5.1.0 brauchen wir Alpha 21.x → priorisiere beta-Branch alpha21.2
      PREFERRED_BRANCH_NAME="${PREFERRED_BRANCH_NAME:-alpha21.2}"
      ;;
    3)
      INSTALL_DARKNESS_FALLS=1
      DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL:-https://dev.azure.com/KhaineUK/f8438d9f-d741-420b-9429-f0838ed77e7f/_apis/git/repositories/80d717da-eb1e-4211-b0c2-eae2d478e749/items?path=/&versionDescriptor%5BversionOptions%5D=0&versionDescriptor%5BversionType%5D=0&versionDescriptor%5Bversion%5D=main&resolveLfs=true&%24format=zip&api-version=5.0&download=true}"
      # Für DF V6 brauchen wir 1.0 → public (kein -beta)
      PREFERRED_BRANCH_NAME="${PREFERRED_BRANCH_NAME:-public}"
      ;;
    *)
      INSTALL_DARKNESS_FALLS=0
      DARKNESS_FALLS_URL=""
      PREFERRED_BRANCH_NAME=""
      ;;
  esac
else
  # Non-interaktiv: respektiere bereits gesetzte Variablen (z.B. via ENV)
  :
fi

# Persistiere die Entscheidung für spätere Tasks (ohne config.env zu ändern)
cat > "${BASE_DIR}/config.local" <<EOF
INSTALL_DARKNESS_FALLS=${INSTALL_DARKNESS_FALLS}
DARKNESS_FALLS_URL="${DARKNESS_FALLS_URL}"
MODS_DIR="${MODS_DIR}"
PREFERRED_BRANCH_NAME="${PREFERRED_BRANCH_NAME}"
EOF

if [ "${INSTALL_DARKNESS_FALLS}" -eq 1 ]; then
  log "DF wird installiert. URL: ${DARKNESS_FALLS_URL}"
  log "Bevorzugter 7DTD-Branch: ${PREFERRED_BRANCH_NAME:-<none>}"
else
  log "DF wird NICHT installiert."
fi
