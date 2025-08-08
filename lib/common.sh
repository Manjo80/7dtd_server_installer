# 7dtd-installer/lib/common.sh
#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

# kleine Log-Helfer
log() { printf '[*] %s\n' "$*"; }
ok()  { printf '[+] %s\n' "$*"; }
err() { printf '[!] %s\n' "$*" >&2; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Dieses Skript muss als root laufen."
    exit 1
  fi
}

# apt install (idempotent), ohne recommendeds
ensure_pkgs() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get -o Dpkg::Options::="--force-confnew" full-upgrade -y
  apt-get install -y --no-install-recommends "$@"
}

# CRLF säubern (nur wenn nötig)
strip_crlf() {
  sed -i 's/\r$//' "$1" 2>/dev/null || true
}

# SteamCMD sicher ausführen (im eigenen Verzeichnis, damit relative Pfade stimmen)
steamcmd_exec() {
  ( cd "${STEAMCMD_DIR}" && bash ./steamcmd.sh "$@" )
}

# Here-Doc Trap (tmp cleanup) — robust bei set -u
trap_rm_tmp() {
  local __var="$1"
  trap "[[ -n \"\${$__var:-}\" ]] && rm -f \"\${$__var}\"; trap - RETURN" RETURN
}
