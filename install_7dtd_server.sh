#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Fehler in Zeile $LINENO" >&2' ERR

# ======= Konfig (per Env überschreibbar) =======
APP_USER="${APP_USER:-sdays}"                            # Nutzer muss mit Buchstabe beginnen (oder --allow-bad-names)
APP_HOME="/home/${APP_USER}"
INSTALL_DIR="${INSTALL_DIR:-$APP_HOME/7days-server}"
APPID="${APPID:-294420}"                                 # 7 Days to Die Dedicated Server
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
STEAMCMD_BIN="${STEAMCMD_BIN:-/opt/steamcmd/steamcmd.sh}"  # direkter Aufruf (kein Symlink-Problem)
SCREEN_NAME="${SCREEN_NAME:-7d2d}"
SERVER_PARAMS="${SERVER_PARAMS:- -configfile=serverconfig.xml -logfile 7d2d.log}"
# =================================================

# ---- CLI-Flags -------------------------------------------------
SELECTED_BRANCH="${SELECTED_BRANCH:-}"
BETAPASS="${BETAPASS:-}"
NON_INTERACTIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --appid)           APPID="$2"; shift 2 ;;
    --branch)          SELECTED_BRANCH="$2"; shift 2 ;;
    --betapass)        BETAPASS="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Dieses Skript muss als root laufen." >&2
    exit 1
  fi
}

pkg_install() {
  echo "[*] System aktualisieren und Pakete installieren..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get -o Dpkg::Options::="--force-confnew" full-upgrade -y
  apt-get install -y --no-install-recommends \
    sudo ca-certificates tzdata wget curl xz-utils tar nano screen \
    telnet netcat-openbsd file procps

  # 32-bit Libs für Steam/7DTD (beide Varianten abdecken)
  if apt-cache show lib32gcc-s1 >/dev/null 2>&1; then
    apt-get install -y lib32gcc-s1 || true
  elif apt-cache show lib32gcc1 >/dev/null 2>&1; then
    apt-get install -y lib32gcc1 || true
  fi
  apt-get install -y lib32stdc++6 || true
}

ensure_user() {
  echo "[*] Prüfe/erstelle User ${APP_USER}..."
  if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "${APP_USER}" \
      || adduser --disabled-password --gecos "" --allow-bad-names "${APP_USER}"
  fi
}

install_steamcmd() {
  echo "[*] Installiere SteamCMD (idempotent)..."
  mkdir -p "${STEAMCMD_DIR}"
  cd "${STEAMCMD_DIR}"

  # Laden nur, wenn nichts da
  if [ ! -f steamcmd.sh ] && [ ! -f steamcmd_linux.tar.gz ]; then
    wget -q http://media.steampowered.com/installer/steamcmd_linux.tar.gz
  fi
  # Entpacken nur, wenn fehlt
  if [ ! -f steamcmd.sh ] && [ -f steamcmd_linux.tar.gz ]; then
    tar xzf steamcmd_linux.tar.gz
  fi

  # Optionaler Wrapper in /usr/games/steamcmd (bequeme Abkürzung, aber wir nutzen STEAMCMD_BIN direkt)
  if [ ! -x /usr/games/steamcmd ]; then
    cat >/usr/games/steamcmd <<'EOF'
#!/usr/bin/env bash
cd /opt/steamcmd
exec bash ./steamcmd.sh "$@"
EOF
    chmod +x /usr/games/steamcmd
  fi

  # Sicherstellen, dass linux32-Verzeichnis vorhanden ist
  [ -d "${STEAMCMD_DIR}/linux32" ] || {
    [ -f steamcmd_linux.tar.gz ] && tar xzf steamcmd_linux.tar.gz
  }

  echo "[+] SteamCMD bereit: ${STEAMCMD_BIN}"
}

choose_appid() {
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    echo "[*] AppID (non-interactive): $APPID"
    return
  fi
  echo
  echo "Standard-AppID ist 294420 (7 Days to Die Dedicated Server)."
  read -rp "Andere AppID verwenden? (Enter für ${APPID}): " inp
  inp="${inp:-$APPID}"
  if [[ "$inp" =~ ^[0-9]+$ ]]; then
    APPID="$inp"
  else
    echo "Ungültige AppID – bleibe bei ${APPID}."
  fi
  echo "[+] Verwende AppID: $APPID"
}

choose_branch() {
  # Steam App-Info holen
  local tmp; tmp="$(mktemp)"
  trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"; trap - RETURN' RETURN
  ( cd "${STEAMCMD_DIR}" && bash ./steamcmd.sh +login anonymous +app_info_print "${APPID}" +quit ) >"$tmp" || true

  BRANCHES=()
  declare -A BR_BUILDID
  declare -A BR_TIME

  local in_branches=0 in_this=0 curr=""
  while IFS= read -r line; do
    # trim
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    if [[ "$line" == '"branches"' ]]; then in_branches=1; continue; fi
    (( in_branches==1 )) || continue
    [[ "$line" == "}" ]] && break

    if [[ "$line" =~ ^\"([A-Za-z0-9._-]+)\"\s*\{$ ]]; then
      curr="${BASH_REMATCH[1]}"; in_this=1
      [[ "$curr" != "local" ]] && BRANCHES+=("$curr")
      continue
    fi
    [[ $in_this -eq 1 ]] || continue
    [[ "$line" == "}" ]] && { in_this=0; curr=""; continue; }

    if [[ "$line" =~ ^\"buildid\"\s+\"([0-9]+)\"$ ]]; then
      BR_BUILDID["$curr"]="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\"timeupdated\"\s+\"([0-9]+)\"$ ]]; then
      BR_TIME["$curr"]="${BASH_REMATCH[1]}"
    fi
  done <"$tmp"

  [ ${#BRANCHES[@]} -eq 0 ] && BRANCHES=(public)

  # Falls via Flag vorgegeben → nur validieren
  if [ -n "$SELECTED_BRANCH" ]; then
    local found=0
    for b in "${BRANCHES[@]}"; do [[ "$b" == "$SELECTED_BRANCH" ]] && found=1 && break; done
    if [ $found -eq 0 ]; then
      echo "[!] Branch '$SELECTED_BRANCH' nicht gefunden. Verfügbare: ${BRANCHES[*]}" >&2
      exit 1
    fi
    echo "[*] Verwende Branch (non-interactive): $SELECTED_BRANCH"
    return
  fi

  echo "Verfügbare Branches (mit BuildID / Zeit):"
  local i=1
  for b in "${BRANCHES[@]}"; do
    local when=""
    if [[ -n "${BR_TIME[$b]:-}" ]]; then
      when="$(date -d @"${BR_TIME[$b]}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${BR_TIME[$b]}")"
    fi
    printf "  [%d] %-24s buildid=%-12s %s\n" "$i" "$b" "${BR_BUILDID[$b]:-?}" "${when}"
    ((i++))
  done
  read -rp "Wähle Branch [1-${#BRANCHES[@]}] (Default 1=public): " choice
  choice="${choice:-1}"
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#BRANCHES[@]} ]; then
    echo "Ungültig, nehme 1."
    choice=1
  fi
  SELECTED_BRANCH="${BRANCHES[$((choice-1))]}"

  if [ "$SELECTED_BRANCH" != "public" ] && [ -z "$BETAPASS" ] && [ "$NON_INTERACTIVE" -eq 0 ]; then
    read -rp "Beta-Passwort für '${SELECTED_BRANCH}' (leer, falls keins): " BETAPASS
  fi
  echo "[+] Gewählter Branch: $SELECTED_BRANCH"
}

install_server() {
  echo "[*] Installiere nach ${INSTALL_DIR} (AppID: ${APPID}, Branch: ${SELECTED_BRANCH:-public})..."
  mkdir -p "${INSTALL_DIR}"
  chown -R "${APP_USER}:${APP_USER}" "${APP_HOME}"

  printf "%s\n" "${APPID}" > "${INSTALL_DIR}/.appid"
  printf "%s\n" "${SELECTED_BRANCH:-public}" > "${INSTALL_DIR}/.branch"
  chown "${APP_USER}:${APP_USER}" "${INSTALL_DIR}/.appid" "${INSTALL_DIR}/.branch"

  local cmd=(+force_install_dir "${INSTALL_DIR}" +login anonymous +app_update "${APPID}")
  if [ -n "${SELECTED_BRANCH:-}" ] && [ "${SELECTED_BRANCH}" != "public" ]; then
    if [ -n "${BETAPASS:-}" ]; then
      cmd+=(-beta "${SELECTED_BRANCH}" -betapassword "${BETAPASS}")
    else
      cmd+=(-beta "${SELECTED_BRANCH}")
    fi
  fi
  cmd+=(validate +quit)

  sudo -u "${APP_USER}" -H bash -lc "
    cd '${STEAMCMD_DIR}'
    bash ./steamcmd.sh ${cmd[*]}
  "
}

write_scripts() {
  echo "[*] Lege Manage- und Update-Skripte an..."
  install -d -m 755 "${INSTALL_DIR}/bin"
  chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

  # manage.sh
  cat > "${INSTALL_DIR}/bin/manage.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEAMCMD="/opt/steamcmd/steamcmd.sh"
APPID="$(tr -d '[:space:]' < "${INSTALL_DIR}/.appid" 2>/dev/null || echo 294420)"
SCREEN_NAME="${SCREEN_NAME:-7d2d}"
SERVER_PARAMS="${SERVER_PARAMS:- -configfile=serverconfig.xml -logfile 7d2d.log}"
TELNET_HOST="127.0.0.1"
TELNET_PORT="8081"
TELNET_PASS=""

cd "$INSTALL_DIR"
require_screen() { command -v screen >/dev/null || { echo "screen fehlt: apt install screen"; exit 1; }; }
is_running() { screen -list | grep -q "\.${SCREEN_NAME}\s"; }

start_srv() {
  require_screen
  if is_running; then echo "Schon gestartet."; exit 0; fi
  [ -x ./startserver.sh ] || { echo "startserver.sh fehlt/ist nicht ausführbar in $INSTALL_DIR"; exit 1; }
  screen -dmS "$SCREEN_NAME" bash -lc "./startserver.sh ${SERVER_PARAMS}"
  sleep 2
  if is_running; then echo "Gestartet."; else echo "Start fehlgeschlagen (Logs prüfen)."; exit 1; fi
}

stop_srv() {
  if ! is_running; then echo "Nicht gestartet."; exit 0; fi
  if [ -n "$TELNET_PASS" ]; then
    if command -v telnet >/dev/null; then
      { sleep 1; echo "$TELNET_PASS"; sleep 1; echo "shutdown"; sleep 1; } | telnet "$TELNET_HOST" "$TELNET_PORT" || true
    elif command -v nc >/dev/null; then
      { sleep 1; echo "$TELNET_PASS"; sleep 1; echo "shutdown"; sleep 1; } | nc "$TELNET_HOST" "$TELNET_PORT" || true
    fi
    sleep 3
  fi
  screen -S "$SCREEN_NAME" -X quit || true
  for i in {1..10}; do
    if ! is_running; then echo "Gestoppt."; return 0; fi
    sleep 1
  done
  echo "Stop hat zu lange gedauert."; exit 1
}

status_srv() { if is_running; then echo "Läuft (screen: $SCREEN_NAME)."; else echo "Gestoppt."; exit 3; fi; }
update_srv() { exec "$INSTALL_DIR/bin/update.sh"; }

case "${1:-}" in
  start) start_srv ;;
  stop) stop_srv ;;
  restart) stop_srv; start_srv ;;
  status) status_srv ;;
  update) update_srv ;;
  *) echo "Usage: $0 {start|stop|status|restart|update}"; exit 1 ;;
esac
EOS
  chmod +x "${INSTALL_DIR}/bin/manage.sh"
  chown "${APP_USER}:${APP_USER}" "${INSTALL_DIR}/bin/manage.sh"

  # update.sh (liest .appid/.branch, listet Branches mit Build/Zeit)
  cat > "${INSTALL_DIR}/bin/update.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEAMCMD="/opt/steamcmd/steamcmd.sh"
APPID="$(tr -d '[:space:]' < "${INSTALL_DIR}/.appid" 2>/dev/null || echo 294420)"
cd "$INSTALL_DIR"

default_branch="$(tr -d '[:space:]' < "${INSTALL_DIR}/.branch" 2>/dev/null || echo public)"
if [ ! -x "$STEAMCMD" ]; then
  echo "steamcmd nicht gefunden unter $STEAMCMD"
  exit 1
fi

tmp="$(mktemp)"
trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"; trap - RETURN' RETURN
echo "[*] Hole Branch-Infos..."
( cd /opt/steamcmd && bash ./steamcmd.sh +login anonymous +app_info_print "$APPID" +quit ) >"$tmp" || true

branches=()
declare -A BR_BUILDID
declare -A BR_TIME
in_branches=0
in_this=0
curr=""
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  if [[ "$line" == '"branches"' ]]; then in_branches=1; continue; fi
  (( in_branches==1 )) || continue
  [[ "$line" == "}" ]] && break
  if [[ "$line" =~ ^\"([A-Za-z0-9._-]+)\"\s*\{$ ]]; then
    curr="${BASH_REMATCH[1]}"; in_this=1
    [[ "$curr" != "local" ]] && branches+=("$curr")
    continue
  fi
  [[ $in_this -eq 1 ]] || continue
  [[ "$line" == "}" ]] && { in_this=0; curr=""; continue; }
  if [[ "$line" =~ ^\"buildid\"\s+\"([0-9]+)\"$ ]]; then
    BR_BUILDID["$curr"]="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\"timeupdated\"\s+\"([0-9]+)\"$ ]]; then
    BR_TIME["$curr"]="${BASH_REMATCH[1]}"
  fi
done <"$tmp"

[ ${#branches[@]} -eq 0 ] && branches=("public")

echo "Verfügbare Branches:"
def_idx=1
for i in "${!branches[@]}"; do
  when=""
  if [[ -n "${BR_TIME[${branches[$i]}]:-}" ]]; then
    when="$(date -d @"${BR_TIME[${branches[$i]}]}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${BR_TIME[${branches[$i]}]}")"
  fi
  printf "  [%d] %-24s buildid=%-12s %s\n" "$((i+1))" "${branches[$i]}" "${BR_BUILDID[${branches[$i]}]:-?}" "${when}"
  [ "${branches[$i]}" = "$default_branch" ] && def_idx="$((i+1))"
done

read -rp "Wähle Branch [1-${#branches[@]}] (Default ${def_idx}=${default_branch}): " choice
choice="${choice:-$def_idx}"
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#branches[@]} ]; then
  echo "Ungültig, nehme ${def_idx}."
  choice="$def_idx"
fi
BRANCH="${branches[$((choice-1))]}"

BETA_ARGS=()
if [ "$BRANCH" != "public" ]; then
  read -rp "Beta-Passwort für '${BRANCH}' (leer, falls keins): " BETAPASS
  if [ -n "${BETAPASS:-}" ]; then
    BETA_ARGS=(-beta "$BRANCH" -betapassword "$BETAPASS")
  else
    BETA_ARGS=(-beta "$BRANCH")
  fi
fi

echo "$BRANCH" > "${INSTALL_DIR}/.branch"
echo "[*] Update läuft auf Branch: $BRANCH"
( cd /opt/steamcmd && bash ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update "$APPID" "${BETA_ARGS[@]}" validate +quit )
echo "[+] Update fertig."
EOS
  chmod +x "${INSTALL_DIR}/bin/update.sh"
  chown "${APP_USER}:${APP_USER}" "${INSTALL_DIR}/bin/update.sh"
}

tweak_serverconfig() {
  echo "[*] Serverconfig minimal anpassen (Telnet aktivieren)..."
  local cfg="${INSTALL_DIR}/serverconfig.xml"
  if [ -f "${cfg}" ]; then
    local pass
    pass="$(openssl rand -hex 6 2>/dev/null || echo 'changeme')"
    sed -i 's#name="TelnetEnabled" value="false"#name="TelnetEnabled" value="true"#' "${cfg}" || true
    sed -i 's#name="TelnetPort" value="8081"#name="TelnetPort" value="8081"#' "${cfg}" || true
    if grep -q 'name="TelnetPassword"' "${cfg}"; then
      sed -i "s#name=\"TelnetPassword\" value=\".*\"#name=\"TelnetPassword\" value=\"${pass}\"#" "${cfg}" || true
    fi
    chown "${APP_USER}:${APP_USER}" "${cfg}"
    echo "[+] Telnet Passwort: ${pass}"
  else
    echo "[!] serverconfig.xml nicht gefunden – erster Start erzeugt sie ggf.."
  fi
}

setup_systemd() {
  echo "[*] Systemd-Service anlegen (falls verfügbar)..."
  if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/7d2d.service <<EOF
[Unit]
Description=7 Days to Die Server
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/manage.sh start
ExecStop=${INSTALL_DIR}/bin/manage.sh stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/7d2d.service
    systemctl daemon-reload
    systemctl enable --now 7d2d || true
    systemctl status 7d2d --no-pager || true
  else
    echo "[!] Kein systemd im Container. Starte manuell:"
    echo "    sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh start"
  fi
}

summary() {
  cat <<EOF

==================== FERTIG ====================
User:        ${APP_USER}
Install:     ${INSTALL_DIR}
SteamCMD:    ${STEAMCMD_BIN} (Wrapper /usr/games/steamcmd vorhanden)
Branch:      ${SELECTED_BRANCH:-public}
Service:     7d2d (falls systemd vorhanden)

Befehle:
  systemctl start|stop|status 7d2d
  systemctl restart 7d2d
  sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh update   # Branch wählen
  sudo -u ${APP_USER} ${INSTALL_DIR}/bin/manage.sh status

Config:
  ${INSTALL_DIR}/serverconfig.xml (Telnet aktiv, Port 8081)
Ports (Host/Firewall):
  UDP 26900–26903, TCP 26900; Telnet nur intern (TCP 8081)
================================================
EOF
}

main() {
  require_root
  pkg_install
  ensure_user
  install_steamcmd
  choose_appid
  choose_branch
  install_server
  write_scripts
  tweak_serverconfig
  setup_systemd
  summary
}

main "$@"
