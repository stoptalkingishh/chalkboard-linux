#!/usr/bin/env bash

set -Eeuo pipefail

STATE_DIR="${CHALKBOARD_STATE_DIR:-/var/lib/chalkboard}"
MODE_MARKER="$STATE_DIR/gcompris-mode-enabled"
SDDM_CONFIG=/etc/sddm.conf.d/95-chalkboard-gcompris.conf
SDDM_TEMPLATE=/usr/local/share/chalkboard/gcompris-sddm.conf
SESSION_FILE=/usr/local/share/wayland-sessions/chalkboard-gcompris.desktop

log() {
  printf '[chalkboard] %s\n' "$*"
}

die() {
  printf '[chalkboard] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run this command as root, for example with sudo"
[[ $# -eq 1 ]] || die "usage: chalkboard-gcompris-mode {enable|disable|status}"

install -d -o root -g root -m 0700 "$STATE_DIR"
exec 9>"$STATE_DIR/gcompris-mode.lock"
flock 9

case "$1" in
  enable)
    [[ -f "$STATE_DIR/deployed" ]] || die "run the Chalkboard deployment first"
    [[ -x /usr/bin/cage ]] || die "the Fedora cage package is not installed"
    [[ -x /usr/bin/gcompris-qt ]] || die "the Fedora gcompris-qt package is not installed"
    [[ -x /usr/local/libexec/chalkboard-gcompris-session ]] || die "the GCompris session runner is not installed"
    [[ -f "$SESSION_FILE" && -f "$SDDM_TEMPLATE" ]] || die "the GCompris session files are not installed"
    getent passwd chalkboard >/dev/null || die "account chalkboard does not exist"
    if id -nG chalkboard | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'; then
      die "account chalkboard is an administrator"
    fi

    touch "$MODE_MARKER"
    chmod 0600 "$MODE_MARKER"
    install -D -o root -g root -m 0644 "$SDDM_TEMPLATE" "$SDDM_CONFIG.tmp"
    mv -f "$SDDM_CONFIG.tmp" "$SDDM_CONFIG"
    restorecon -F "$SDDM_CONFIG" "$MODE_MARKER" 2>/dev/null || true
    log "GCompris mode enabled; reboot to enter it"
    ;;
  disable)
    rm -f "$SDDM_CONFIG"
    rm -f "$MODE_MARKER"
    log "GCompris mode disabled; reboot to return to the child Plasma desktop"
    ;;
  status)
    if [[ -f "$MODE_MARKER" && -f "$SDDM_CONFIG" ]] && \
        cmp -s "$SDDM_TEMPLATE" "$SDDM_CONFIG"; then
      printf 'enabled\n'
    elif [[ ! -e "$MODE_MARKER" && ! -e "$SDDM_CONFIG" ]]; then
      printf 'disabled\n'
    else
      printf 'inconsistent\n' >&2
      exit 1
    fi
    ;;
  *)
    die "usage: chalkboard-gcompris-mode {enable|disable|status}"
    ;;
esac
