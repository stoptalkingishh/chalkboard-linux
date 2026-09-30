#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_fedora

CHILD_USER="$(<"$STATE_DIR/child-user")"
# This is the terminal lockdown step, so it re-checks the account properties that
# deploy.sh checked. An account that gained administrator rights between the two
# phases must not be finalized.
[[ "$CHILD_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
  || die "invalid child account name in $STATE_DIR/child-user"
getent passwd "$CHILD_USER" >/dev/null || die "account $CHILD_USER does not exist"
[[ "$(id -u "$CHILD_USER")" -ge 1000 ]] || die "refusing to finalize a system account"
if id -nG "$CHILD_USER" | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'; then
  die "account $CHILD_USER is an administrator; refusing to finalize"
fi
CHILD_HOME="$(child_home "$CHILD_USER")"
MARKER="$CHILD_HOME/.local/state/chalkboard/plasma-provisioned"
[[ -f "$MARKER" ]] || die "Plasma has not finished first-login provisioning"

log "locking down the child app menu to the curated allowlist"
CHALKBOARD_CHILD_USER="$CHILD_USER" bash "$SCRIPT_DIR/curate-app-menu.sh" "$CHILD_USER"

log "installing immutable child-only KDE policy"
backup_file /etc/xdg/chalkboard/kdeglobals
backup_file /etc/xdg/chalkboard/kglobalshortcutsrc
install -D -o root -g root -m 0644 \
  /usr/local/share/chalkboard/policy/kdeglobals /etc/xdg/chalkboard/kdeglobals
install -D -o root -g root -m 0644 \
  /usr/local/share/chalkboard/policy/kglobalshortcutsrc /etc/xdg/chalkboard/kglobalshortcutsrc
restorecon -RF /etc/xdg/chalkboard 2>/dev/null || true

log "confirming the child app menu matches the allowlist"
# The verifier resolves the child's home directory from the account name, so it
# needs the same name this script is finalizing. Without it, a non-default child
# account failed with "unknown child user" and finalization aborted.
CHALKBOARD_CHILD_USER="$CHILD_USER" /usr/local/libexec/chalkboard-check-app-menu

touch "$STATE_DIR/finalized"

log "lockdown finalized; reboot to load immutable policy"
