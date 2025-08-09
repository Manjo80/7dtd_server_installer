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

# --- XML-Property setzen (anlegen falls fehlend) ---
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

# Falschen Key aus früheren Läufen sicher entfernen
xmlstarlet ed -L -d "//property[@name='ServerLanguage']" "${CFG}" 2>/dev/null || true

NONI="${NON_INTERACTIVE:-0}"
DF_ON="${INSTALL_DARKNESS_FALLS:-0}"

# --- feste Listen für Region / Sprache ---
REGIONS=(
  "NorthAmericaEast" "NorthAmericaWest" "CentralAmerica" "SouthAmerica"
  "Europe" "Russia" "Asia" "MiddleEast" "Africa" "Oceania"
)
LANGS=("English" "German")

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

VISIBILITY_DEFAULT="2"       # 0=hidden, 1=friends, 2=public
WORLDSIZE_MULT_DEFAULT="8"   # 8 => 8192

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
  # --- GameWorld / Seed Logik ---
  read -rp "Eigenen RWG-Seed verwenden? (j/N): " USE_SEED_ANS
  USE_SEED=0; [[ "${USE_SEED_ANS}" =~ ^[Jj]$ ]] && USE_SEED=1

  if [ "${USE_SEED}" -eq 1 ]; then
    # Bei eigenem Seed MUSS GameWorld=RWG
    GAME_WORLD="RWG"
    read -rp "Seed (z.B. 'MySeed123'): " WORLD_SEED
    WORLD_SEED="${WORLD_SEED:-MySeed}"
  else
    if [ "${DF_ON}" -eq 1 ]; then
      echo "GameWorld wählen (Darkness Falls):"
      echo "  1) DFalls-Navezgane (kein Seed)"
      echo "  2) RWG (mit Seed)"
      read -rp "Auswahl [1-2, Default 2]: " gwc
      case "${gwc:-2}" in
        1) GAME_WORLD="DFalls-Navezgane"; WORLD_SEED="";;
        *) GAME_WORLD="RWG"; read -rp "Seed (z.B. 'MySeed123'): " WORLD_SEED; WORLD_SEED="${WORLD_SEED:-MySeed}";;
      esac
    else
      echo "GameWorld wählen (Vanilla):"
      echo "  1) Navezgane (Festkarte)"
      echo "  2) RWG (Random World Generation mit Seed)"
      read -rp "Auswahl [1-2, Default 2]: " gwc
      case "${gwc:-2}" in
        1) GAME_WORLD="Navezgane"; WORLD_SEED="";;
        *) GAME_WORLD="RWG"; read -rp "Seed (z.B. 'MySeed123'): " WORLD_SEED; WORLD_SEED="${WORLD_SEED:-MySeed}";;
      esac
    fi
  fi

  echo
  echo "WorldGenSize Multiplikator (4,6,8,10,12,14,16 / 0 = Max 16384)"
  read -rp "[${WORLDSIZE_MULT_DEFAULT}]: " WS_MULT
  WS_MULT="${WS_MULT:-$WORLDSIZE_MULT_DEFAULT}"
  if [[ "$WS_MULT" = "0" ]]; then
    WORLD_GEN_SIZE=16384
  else
    case "$WS_MULT" in
      4|6|8|10|12|14|16) WORLD_GEN_SIZE=$(( WS_MULT * 1024 )) ;;
      *) echo "Ungültig, nehme Default ${WORLDSIZE_MULT_DEFAULT} -> 8192"; WORLD_GEN_SIZE=$(( WORLDSIZE_MULT_DEFAULT * 1024 )) ;;
    esac
  fi

  read -rp "ServerPort        [${PORT_DEFAULT}]: " SERVER_PORT
  SERVER_PORT="${SERVER_PORT:-$PORT_DEFAULT}"

  read -rp "MaxPlayers        [${MAX_PLAYERS_DEFAULT}]: " MAX_PLAYERS
  MAX_PLAYERS="${MAX_PLAYERS:-$MAX_PLAYERS_DEFAULT}"

  # --- Region ---
  echo "Region auswählen:"
  select REG_CHOICE in "${REGIONS[@]}"; do
    [ -n "${REG_CHOICE:-}" ] && REGION="$REG_CHOICE" && break
  done

  # --- Sprache ---
  echo "Sprache auswählen:"
  select LANG_CHOICE in "${LANGS[@]}"; do
    [ -n "${LANG_CHOICE:-}" ] && SERVER_LANG="$LANG_CHOICE" && break
  done

  read -rp "ServerVisibility (0=hidden,1=friends,2=public) [${VISIBILITY_DEFAULT}]: " SERVER_VIS
  SERVER_VIS="${SERVER_VIS:-$VISIBILITY_DEFAULT}"
  case "$SERVER_VIS" in 0|1|2) : ;; *) echo "Ungültig, nehme ${VISIBILITY_DEFAULT}"; SERVER_VIS="${VISIBILITY_DEFAULT}";; esac

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
  # Non-interaktiv: sinnvolle Defaults
  SERVER_NAME="${SERVER_NAME_DEFAULT}"
  SERVER_DESC="${SERVER_DESC_DEFAULT}"
  GAME_NAME="${GAME_NAME_DEFAULT}"
  if [ "${DF_ON}" -eq 1 ]; then
    GAME_WORLD="DFalls-Large"
  else
    GAME_WORLD="RWG"
  fi
  WORLD_SEED=""  # kein eigener Seed im non-interactive Default
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

# --- Properties schreiben ---
set_prop "ServerName"           "${SERVER_NAME}"
set_prop "ServerDescription"    "${SERVER_DESC}"
set_prop "ServerPort"           "${SERVER_PORT}"
set_prop "ServerMaxPlayerCount" "${MAX_PLAYERS}"
set_prop "ServerPassword"       "${SERVER_PASS}"

set_prop "Region"               "${REGION}"
# WICHTIG: richtiger Key ist "Language"
set_prop "Language"             "${SERVER_LANG}"
set_prop "ServerVisibility"     "${SERVER_VIS}"

set_prop "GameName"             "${GAME_NAME}"
set_prop "GameWorld"            "${GAME_WORLD}"

# Seed nur, wenn gesetzt (bei RWG)
if [ -n "${WORLD_SEED:-}" ]; then
  set_prop "WorldGenSeed" "${WORLD_SEED}"
fi

# WorldGenSize immer setzen
set_prop "WorldGenSize"         "${WORLD_GEN_SIZE}"

# Telnet
set_prop "TelnetEnabled"        "${TELNET_ENABLED}"
set_prop "TelnetPort"           "${TELNET_PORT}"
set_prop "TelnetPassword"       "${TELNET_PASS}"

ok "Konfiguration aktualisiert: ${CFG}"

cat <<EON

Kurzüberblick:
  Name:         ${SERVER_NAME}
  World:        ${GAME_WORLD}
  Seed:         ${WORLD_SEED:-<kein eigener Seed>}
  WorldGenSize: ${WORLD_GEN_SIZE}
  GameName:     ${GAME_NAME}
  Port:         ${SERVER_PORT}
  MaxPlayers:   ${MAX_PLAYERS}
  Region:       ${REGION}
  Language:     ${SERVER_LANG}
  Visibility:   ${SERVER_VIS}
  Telnet:       ${TELNET_ENABLED} (Port ${TELNET_PORT})

Backup liegt unter:
  ${backup}

EON
