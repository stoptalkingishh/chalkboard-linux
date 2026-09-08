#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_fedora

CHILD_USER="$(<"$STATE_DIR/child-user")"
CHILD_HOME="$(child_home "$CHILD_USER")"
MARKER="$CHILD_HOME/.local/state/chalkboard/plasma-provisioned"
[[ -f "$MARKER" ]] || die "Plasma has not finished first-login provisioning"

log "locking down the child app menu to the curated allowlist"
"$SCRIPT_DIR/curate-app-menu.sh" "$CHILD_USER"

log "installing immutable child-only KDE policy"
backup_file /etc/xdg/chalkboard/kdeglobals
backup_file /etc/xdg/chalkboard/kglobalshortcutsrc
install -D -o root -g root -m 0644 \
  /usr/local/share/chalkboard/policy/kdeglobals /etc/xdg/chalkboard/kdeglobals
install -D -o root -g root -m 0644 \
  /usr/local/share/chalkboard/policy/kglobalshortcutsrc /etc/xdg/chalkboard/kglobalshortcutsrc
restorecon -RF /etc/xdg/chalkboard 2>/dev/null || true
touch "$STATE_DIR/finalized"

log "lockdown finalized; reboot to load immutable policy"
