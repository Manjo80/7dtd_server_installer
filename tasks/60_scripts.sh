# 7dtd-installer/tasks/60_scripts.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
[ -f "${BASE_DIR}/config.local" ] && source "${BASE_DIR}/config.local"
source "${BASE_DIR}/lib/common.sh"

log "Erzeuge manage.sh / update.sh…"
install -d -m 755 "${INSTALL_DIR}/bin"
# manage.sh
cat > "${INSTALL_DIR}/bin/manage.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# update.sh
cat > "${INSTALL_DIR}/bin/update.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPID="$(tr -d '[:space:]' < "${INSTALL_DIR}/.appid" 2>/dev/null || echo 294420)"
cd "$INSTALL_DIR"

tmp="$(mktemp)"; trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"; trap - RETURN' RETURN
echo "[*] Hole Branch-Infos…"
/opt/steamcmd/steamcmd.sh +login anonymous +app_info_print "$APPID" +quit >"$tmp" || true

branches=(); declare -A BR_BUILDID; declare -A BR_TIME
in_branches=0; in_this=0; curr=""
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  if [[ "$line" == '"branches"' ]]; then in_branches=1; continue; fi
  (( in_branches==1 )) || continue
  [[ "$line" == "}" ]] && break
  if [[ "$line" =~ ^\"([A-Za-z0-9._-]+)\"\s*\{$ ]]; then
    curr="${BASH_REMATCH[1]}"; in_this=1
    [[ "$curr" != "local" ]] && branches+=("$curr"); continue
  fi
  [[ $in_this -eq 1 ]] || continue
  [[ "$line" == "}" ]] && { in_this=0; curr=""; continue; }
  [[ "$line" =~ ^\"buildid\"\s+\"([0-9]+)\"$ ]] && BR_BUILDID["$curr"]="${BASH_REMATCH[1]}"
  [[ "$line" =~ ^\"timeupdated\"\s+\"([0-9]+)\"$ ]] && BR_TIME["$curr"]="${BASH_REMATCH[1]}"
done <"$tmp"

[ ${#branches[@]} -eq 0 ] && branches=("public")

default_branch="$(tr -d '[:space:]' < "${INSTALL_DIR}/.branch" 2>/dev/null || echo public)"
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
[[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#branches[@]} )) || choice="$def_idx"
BRANCH="${branches[$((choice-1))]}"

BETA_ARGS=()
if [ "$BRANCH" != "public" ]; then
  read -rp "Beta-Passwort für '${BRANCH}' (leer, falls keins): " BETAPASS
  [ -n "${BETAPASS:-}" ] && BETA_ARGS=(-beta "$BRANCH" -betapassword "$BETAPASS") || BETA_ARGS=(-beta "$BRANCH")
fi

echo "$BRANCH" > "${INSTALL_DIR}/.branch"
echo "[*] Update läuft auf Branch: $BRANCH"
/opt/steamcmd/steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update "$APPID" "${BETA_ARGS[@]}" validate +quit
echo "[+] Update fertig."
EOS
chmod +x "${INSTALL_DIR}/bin/update.sh"

chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"
ok "Skripte erzeugt."
