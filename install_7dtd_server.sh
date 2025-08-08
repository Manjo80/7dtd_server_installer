#!/usr/bin/env bash
# Falls versehentlich mit /bin/sh gestartet wurde: in bash neu starten
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"

set -euo pipefail
trap 'echo "Fehler in Zeile $LINENO" >&2' ERR

# ======= Konfig (per Env überschreibbar) =======
APP_USER="${APP_USER:-sdays}"                      # Nutzer muss mit Buchstabe beginnen (oder --allow-bad-names)
APP_HOME="/home/${APP_USER}"
INSTALL_DIR="${INSTALL_DIR:-$APP_HOME/7days-server}"
APPID="${APPID:-294420}"                           # 7 Days to Die Dedicated Server
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

  # Bequemer Wrapper (optional)
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
    read -rp "Beta-Passwort fü
