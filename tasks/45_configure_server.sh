#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

CFG="${INSTALL_DIR}/serverconfig.xml"

log "Serverkonfiguration anpassen…"

if [ ! -f "${CFG}" ]; then
  err "serverconfig.xml nicht gefunden unter ${CFG}. Wurde der Server schon installiert (Task 50)?"
  err "Überspringe Config-Task. Starte ./run.sh später erneut, wenn die Datei vorhanden ist."
  exit 0
fi

backup="${CFG}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "${CFG}" "${backup}"
ok "Backup erstellt: ${backup}"

# --- Helfer: XML-Property setzen ---
set_prop() {
  local name="$1" value="$2"
  # Falls Property existiert -> Wert setzen, sonst neues Property anlegen
  if xmlstarlet sel -t -c "//property[@name='${name}']" "${CFG}" >/dev/null 2>&1; then
    xmlstarlet ed -L -u "//property[@name='${name}']/@value" -v "${value}" "${CFG}"
  else
    xmlstarlet ed -L -s "/ServerSettings" -t elem -n "propertyTMP" -v "" \
      -i "//propertyTMP" -t attr -n "name"  -v "${name}" \
      -i "//propertyTMP" -t attr -n "value" -v "${value}" \
      -r "//propertyTMP" -v "property" "${CFG}"
  fi
}

# --- Defaults / Eingaben ---
NONI="${NON_INTERACTIVE:-0}"
DF_ON="${INSTALL_DARKNESS_FALLS:-0}"

# Server Identity
SERVER_NAME_DEFAULT="My 7DTD Server"
SERVER_DESC_DEFAULT="Welcome!"
SERVER_URL_DEFAULT=""

# Gameplay / World
# Hinweis: Wenn eigener Seed -> GameWorld=RWG setzen
GAME_NAME_DEFAULT="MySave"
[ "${DF_ON}" -eq 1 ] && GAME_NAME_DEFAULT="DF-Save"

# Ports & Spieler
PORT_DEFAULT="26900"
MAX_PLAYERS_DEFAULT="8"

# Telnet
TELNET_ENABLED_DEFAULT="true"
TELNET_PORT_DEFAULT="8081"
TELNET_PASS_DEFAULT="$(openssl rand -hex 6 2>/dev/null || echo changeme)"

# Password (optional leer)
SERVER_PASS_DEFAULT=""

if [ "${NONI}" -eq 0 ]; then
  echo
  read -rp "Servername        [${SERVER_NAME_DEFAULT}]: " SERVER_NAME
  SERVER_NAME="${SERVER_NAME:-$SERVER_NAME_DEFAULT}"

  read -rp "Beschreibung      [${SERVER_DESC_DEFAULT}]: " SERVER_DESC
  SERVER_DESC="${SERVER_DESC:-$SERVER_DESC_DEFAULT}"

  read -rp "Website URL       [leer]: " SERVER_URL
  SERVER_URL="${SERVER_URL:-$SERVER_URL_DEFAULT}"

  echo
  read -rp "Spielstand-Name (GameName) [${GAME_NAME_DEFAULT}]: " GAME_NAME
  GAME_NAME="${GAME_NAME:-$GAME_NAME_DEFAULT}"

  echo
  read -rp "Eigenen RWG-Seed verwenden? (j/N): " USE_SEED_ANS
  USE_SEED=0; [[ "${USE_SEED_ANS}" =~ ^[Jj]$ ]] && USE_SEED=1
  if [ "${USE_SEED}" -eq 1 ]; then
    read -rp "Seed (z.B. 'MySeed123'): " WORLD_SEED
    WORLD_SEED="${WORLD_SEED:-MySeed}"
    # Bei eigenem Seed MUSS GameWorld=RWG
    GAME_WORLD="RWG"
  else
    # Vorschläge abhängig von Mod
    if [ "${DF_ON}" -eq 1 ]; then
      echo "GameWorld wählen:"
      echo "  1) DFalls-Navezgane"
      echo "  2) DFalls-Large"
      read -rp "Auswahl [1-2, Default 2]: " gwc
      case "${gwc:-2}" in
        1) GAME_WORLD="DFalls-Navezgane" ;;
        *) GAME_WORLD="DFalls-Large" ;;
      esac
    else
      echo "GameWorld wählen:"
      echo "  1) Navezgane (Festkarte)"
      echo "  2) RWG (Random World Generation)"
      read -rp "Auswahl [1-2, Default 2]: " gwc
      case "${gwc:-2}" in
        1) GAME_WORLD="Navezgane" ;;
        *) GAME_WORLD="RWG" ;;
      esac
    fi
    WORLD_SEED="${WORLD_SEED:-}"   # leer lassen wenn kein eigener Seed
  fi

  echo
  read -rp "ServerPort        [${PORT_DEFAULT}]: " SERVER_PORT
  SERVER_PORT="${SERVER_PORT:-$PORT_DEFAULT}"

  read -rp "MaxPlayers        [${MAX_PLAYERS_DEFAULT}]: " MAX_PLAYERS
  MAX_PLAYERS="${MAX_PLAYERS:-$MAX_PLAYERS_DEFAULT}"

  echo
  read -rp "ServerPassword (leer erlaubt): " SERVER_PASS
  SERVER_PASS="${SERVER_PASS:-$SERVER_PASS_DEFAULT}"

  echo
  read -rp "Telnet aktivieren? (J/n) [${TELNET_ENABLED_DEFAULT}]: " TELNET_EN_ANS
  case "${TELNET_EN_ANS:-}" in
    [Nn]) TELNET_ENABLED="false" ;;
    *)     TELNET_ENABLED="${TELNET_ENABLED_DEFAULT}" ;;
  esac

  read -rp "TelnetPort        [${TELNET_PORT_DEFAULT}]: " TELNET_PORT
  TELNET_PORT="${TELNET_PORT:-$TELNET_PORT_DEFAULT}"

  read -rp "TelnetPassword (leer=random): " TELNET_PASS
  TELNET_PASS="${TELNET_PASS:-$TELNET_PASS_DEFAULT}"

else
  # Non-interaktiv: Defaults + DF-abhängige World
  SERVER_NAME="${SERVER_NAME_DEFAULT}"
  SERVER_DESC="${SERVER_DESC_DEFAULT}"
  SERVER_URL="${SERVER_URL_DEFAULT}"
  GAME_NAME="${GAME_NAME_DEFAULT}"
  if [ "${DF_ON}" -eq 1 ]; then
    GAME_WORLD="DFalls-Large"
  else
    GAME_WORLD="RWG"
  fi
  WORLD_SEED="${WORLD_SEED:-}"     # kein eigener Seed
  SERVER_PORT="${PORT_DEFAULT}"
  MAX_PLAYERS="${MAX_PLAYERS_DEFAULT}"
  SERVER_PASS="${SERVER_PASS_DEFAULT}"
  TELNET_ENABLED="${TELNET_ENABLED_DEFAULT}"
  TELNET_PORT="${TELNET_PORT_DEFAULT}"
  TELNET_PASS="${TELNET_PASS_DEFAULT}"
fi

# --- Werte setzen ---
set_prop "ServerName"           "${SERVER_NAME}"
set_prop "ServerDescription"    "${SERVER_DESC}"
[ -n "${SERVER_URL}" ] && set_prop "ServerWebsiteURL" "${SERVER_URL}"

set_prop "ServerPort"           "${SERVER_PORT}"
set_prop "ServerMaxPlayerCount" "${MAX_PLAYERS}"
set_prop "ServerPassword"       "${SERVER_PASS}"

set_prop "GameName"             "${GAME_NAME}"
set_prop "GameWorld"            "${GAME_WORLD}"

# Seed nur setzen, wenn explizit gewünscht/gesetzt
if [ -n "${WORLD_SEED:-}" ]; then
  set_prop "WorldGenSeed" "${WORLD_SEED}"
else
  # Wenn kein Seed angegeben und GameWorld RWG ist, entferne evtl. alten Seed-Eintrag (optional)
  :
fi

# Telnet
set_prop "TelnetEnabled"  "${TELNET_ENABLED}"
set_prop "TelnetPort"     "${TELNET_PORT}"
set_prop "TelnetPassword" "${TELNET_PASS}"

ok "Konfiguration aktualisiert: ${CFG}"

cat <<EON

Kurzüberblick:
  Name:        ${SERVER_NAME}
  World:       ${GAME_WORLD}
  Seed:        ${WORLD_SEED:-<kein eigener Seed>}
  GameName:    ${GAME_NAME}
  Port:        ${SERVER_PORT}
  MaxPlayers:  ${MAX_PLAYERS}
  Telnet:      ${TELNET_ENABLED} (Port ${TELNET_PORT})

Backup liegt unter:
  ${backup}

EON
