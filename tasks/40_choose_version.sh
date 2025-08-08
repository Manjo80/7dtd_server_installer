# 7dtd-installer/tasks/40_choose_version.sh
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config.env"
source "${BASE_DIR}/lib/common.sh"

# AppID ggf. interaktiv ändern
if [ "${NON_INTERACTIVE}" -eq 0 ]; then
  echo
  echo "Standard-AppID ist ${APPID} (7DTD Dedicated=294420)."
  read -rp "Andere AppID verwenden? (Enter für ${APPID}): " inp
  inp="${inp:-$APPID}"
  if [[ "$inp" =~ ^[0-9]+$ ]]; then APPID="$inp"; else err "Ungültig, bleibe bei ${APPID}"; fi
else
  log "NON_INTERACTIVE: AppID=${APPID}"
fi

# Branchliste auslesen
tmp="$(mktemp)"; trap_rm_tmp tmp
log "Lese Branches/Builds via app_info_print…"
steamcmd_exec +login anonymous +app_info_print "${APPID}" +quit >"$tmp" || true

BRANCHES=()
declare -A BR_BUILDID
declare -A BR_TIME

in_branches=0; in_this=0; curr=""
while IFS= read -r line; do
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
  [[ "$line" =~ ^\"buildid\"\s+\"([0-9]+)\"$ ]] && BR_BUILDID["$curr"]="${BASH_REMATCH[1]}"
  [[ "$line" =~ ^\"timeupdated\"\s+\"([0-9]+)\"$ ]] && BR_TIME["$curr"]="${BASH_REMATCH[1]}"
done <"$tmp"

[ ${#BRANCHES[@]} -eq 0 ] && BRANCHES=(public)

SELECTED_BRANCH="${SELECTED_BRANCH:-}"
if [ -n "${SELECTED_BRANCH}" ]; then
  ok "Branch per Env/Flag vorgegeben: ${SELECTED_BRANCH}"
else
  if [ "${NON_INTERACTIVE}" -eq 1 ]; then
    SELECTED_BRANCH="public"
    ok "NON_INTERACTIVE: setze Branch=${SELECTED_BRANCH}"
  else
    echo "Verfügbare Branches:"
    i=1
    for b in "${BRANCHES[@]}"; do
      when=""; [[ -n "${BR_TIME[$b]:-}" ]] && when="$(date -d @"${BR_TIME[$b]}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${BR_TIME[$b]}")"
      printf "  [%d] %-24s buildid=%-12s %s\n" "$i" "$b" "${BR_BUILDID[$b]:-?}" "$when"
      ((i++))
    done
    read -rp "Wähle Branch [1-${#BRANCHES[@]}] (Default 1=public): " choice
    choice="${choice:-1}"; [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#BRANCHES[@]} )) || choice=1
    SELECTED_BRANCH="${BRANCHES[$((choice-1))]}"
    if [ "$SELECTED_BRANCH" != "public" ]; then
      read -rp "Beta-Passwort für '${SELECTED_BRANCH}' (leer, falls keins): " BETAPASS
    fi
  fi
fi

mkdir -p "${INSTALL_DIR}"
printf "%s\n" "${APPID}" > "${INSTALL_DIR}/.appid"
printf "%s\n" "${SELECTED_BRANCH}" > "${INSTALL_DIR}/.branch"
chown -R "${APP_USER}:${APP_USER}" "${APP_HOME}"
ok "AppID=${APPID}, Branch=${SELECTED_BRANCH}"
