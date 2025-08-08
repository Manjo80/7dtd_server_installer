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

# --- XML-Property setzen ---
set_prop() {
  local name="$1" value="$2"
  if xmlstarlet sel -t -c "//property[@name='${name}']" "${CFG}" >/dev/null 2>&1; then
    xmlstarlet ed -L -u "//property[@name='${name}']/@value" -v "${value}" "${CFG}"
  else
    xmlstarlet ed -L \
      -s "/ServerSettings" -t elem -n "propertyTMP" -v "" \
      -i "//propertyTMP" -t attr -n "name"  -v "${name}" \
      -i "//propertyTMP" -t attr -n "value" -v "${value}" \
      -r "//propertyTMP" -v "property" "${CFG}"
  fi
}

NONI="${NON_INTERACTIVE:-0}"
DF_ON="${INSTALL_DARKNESS_FALLS:-0}"

# --- Defaults ---
SERVER_NAME_DEFAULT="My 7DTD Server"
SERVER_DESC_DEFAULT="Welcome!"
GAME_NAME_DEFAULT="MySave"; [ "${DF_ON}" -eq 1 ] && GAME_NAME_DEFAULT="DF-Save"
PORT_DEFAULT="26900"
MAX_PLAYERS_DEFAULT="8"
TELNET_ENABLED_DEFAULT="true"
TELNET_PORT_DEFAULT="8081"
TELNET_PASS_DEFAULT="$(openssl rand -hex 6 2>/dev/null || echo changeme)"
SERVER_PASS_DEFAULT=""

# NEU: feste Listen
REGIONS=(
  "NorthAmericaEast"
  "NorthAmericaWest"
  "CentralAmerica"
  "SouthAmerica"
  "Europe"
  "Russia"
  "Asia"
  "MiddleEast"
  "Africa"
  "Oceania"
)
LANGS=("English" "German")

VISIBILITY_DEFAULT="2"
WORLDSIZE_MULT_DEFAULT="8"

if [ "${NONI}" -eq 0 ]; then
  echo
  read -rp "Servername        [${SERVER_NAME_DEFAULT}]: " SERVER_NAME
  SERVER_NAME="${SERVER_NAME:-$SERVER_NAME_DEFAULT}"

  read -rp "Beschreibung      [${SERVER_DESC_DEFAULT}]: " SERVER_DESC
  SERVER_DESC="${SERVER_DESC:-$SERVER_DESC_DEFAULT}"

  echo
  read -rp "Spielstand-Name (GameName) [${GAME_NAME_DEFAULT}]: " GAME_NAME
  GAME_NAME="${GAME_NAME:-$GAME_NAME_DEFAULT}"

  echo
  read -rp "Eigenen RWG-Seed verwenden? (j/N): " USE_SEED_ANS
  USE_SEED=0; [[ "${USE_SEED_ANS}" =~ ^[Jj]$ ]] && USE_SEED=1
  if [ "${USE_SEED}" -eq 1 ]; then
    read -rp "Seed: " WORLD_SEED
    WORLD_SEED="${WORLD_SEED:-MySeed}"
    GAME_WORLD="RWG"
  else
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
      echo "  1) Navezgane"
      echo "  2) RWG"
      read -rp "Auswahl [1-2, Default 2]: " gwc
      case "${gwc:-2}" in
        1) GAME_WORLD="Navezgane" ;;
        *) GAME_WORLD="RWG" ;;
      esac
    fi
    WORLD_SEED="${WORLD_SEED:-}"
  fi

  echo
  echo "WorldGenSize Multiplikator (4,6,8,10,12,14,16 / 0 = Max 16384)"
  read -rp "[${WORLDSIZE_MULT_DEFAULT}]: " WS_MULT
  WS_MULT="${WS_MULT:-$WORLDSIZE_MULT_DEFAULT}"
  if [[ "$WS_MULT" = "0" ]]; then
    WORLD_GEN_SIZE=16384
  else
    WORLD_GEN_SIZE=$(( WS_MULT * 1024 ))
  fi

  read -rp "ServerPort [${PORT_DEFAULT}]: " SERVER_PORT
  SERVER_PORT="${SERVER_PORT:-$PORT_DEFAULT}"

  read -rp "MaxPlayers [${MAX_PLAYERS_DEFAULT}]: " MAX_PLAYERS
  MAX_PLAYERS="${MAX_PLAYERS:-$MAX_PLAYERS_DEFAULT}"

  # Region Auswahl
  echo "Region auswählen:"
  select REG_CHOICE in "${REGIONS[@]}"; do
    [ -n "$REG_CHOICE" ] && REGION="$REG_CHOICE" && break
  done

  # Sprache Auswahl
  echo "Sprache auswählen:"
  select LANG_CHOICE in "${LANGS[@]}"; do
    [ -n "$LANG_CHOICE" ] && SERVER_LANG="$LANG_CHOICE" && break
  done

  read -rp "ServerVisibility (0=hidden,1=friends,2=public) [${VISIBILITY_DEFAULT}]: " SERVER_VIS
  SERVER_VIS="${SERVER_VIS:-$VISIBILITY_DEFAULT}"

  read -rp "ServerPassword (leer erlaubt): " SERVER_PASS
  SERVER_PASS="${SERVER_PASS:-$SERVER_PASS_DEFAULT}"

  read -rp "Telnet aktivieren? (J/n) [${TELNET_ENABLED_DEFAULT}]: " TELNET_EN_ANS
  case "${TELNET_EN_ANS:-}" in
    [Nn]) TELNET_ENABLED="false" ;;
    *)     TELNET_ENABLED="${TELNET_ENABLED_DEFAULT}" ;;
  esac
  read -rp "TelnetPort [${TELNET_PORT_DEFAULT}]: " TELNET_PORT
  TELNET_PORT="${TELNET_PORT:-$TELNET_PORT_DEFAULT}"
  read -rp "TelnetPassword (leer=random): " TELNET_PASS
  TELNET_PASS="${TELNET_PASS:-$TELNET_PASS_DEFAULT}"

else
  SERVER_NAME="${SERVER_NAME_DEFAULT}"
  SERVER_DESC="${SERVER_DESC_DEFAULT}"
  GAME_NAME="${GAME_NAME_DEFAULT}"
  GAME_WORLD="$([ "${DF_ON}" -eq 1 ] && echo "DFalls-Large" || echo "RWG")"
  WORLD_SEED=""
  WORLD_GEN_SIZE=$(( WORLDSIZE_MULT_DEFAULT * 1024 ))
  SERVER_PORT="${PORT_DEFAULT}"
  MAX_PLAYERS="${MAX_PLAYERS_DEFAULT}"
  REGION="Europe"
  SERVER_LANG="German"
  SERVER_VIS="${VISIBILITY_DEFAULT}"
  SERVER_PASS="${SERVER_PASS_DEFAULT}"
  TELNET_ENABLED="${TELNET_ENABLED_DEFAULT}"
  TELNET_PORT="${TELNET_PORT_DEFAULT}"
  TELNET_PASS="${TELNET_PASS_DEFAULT}"
fi

# Properties setzen
set_prop "ServerName" "${SERVER_NAME}"
set_prop "ServerDescription" "${SERVER_DESC}"
set_prop "ServerPort" "${SERVER_PORT}"
set_prop "ServerMaxPlayerCount" "${MAX_PLAYERS}"
set_prop "ServerPassword" "${SERVER_PASS}"
set_prop "Region" "${REGION}"
set_prop "ServerLanguage" "${SERVER_LANG}"
set_prop "ServerVisibility" "${SERVER_VIS}"
set_prop "GameName" "${GAME_NAME}"
set_prop "GameWorld" "${GAME_WORLD}"
[ -n "${WORLD_SEED}" ] && set_prop "WorldGenSeed" "${WORLD_SEED}"
set_prop "WorldGenSize" "${WORLD_GEN_SIZE}"
set_prop "TelnetEnabled" "${TELNET_ENABLED}"
set_prop "TelnetPort" "${TELNET_PORT}"
set_prop "TelnetPassword" "${TELNET_PASS}"

ok "Konfiguration aktualisiert: ${CFG}"
