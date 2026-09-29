#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
[[ -d "$BACKUP_DIR/files" ]] || die "no Chalkboard backup was found"

if [[ -x /usr/local/libexec/chalkboard-screen-time ]]; then
  log "disabling screen-time and restoring the child account expiry"
  systemctl disable --now chalkboard-screen-time.timer 2>/dev/null || true
  # Rollback is the last-resort recovery path, so it must not abort before the
  # file restoration below. A corrupt state file or a manually changed account
  # expiry would otherwise strand the device in the locked-down state, which is
  # the opposite of what rollback is for. Warn loudly and carry on instead.
  if ! /usr/local/libexec/chalkboard-screen-time force-release; then
    printf '[chalkboard] WARNING: screen-time force-release failed.\n' >&2
    printf '[chalkboard] WARNING: the child account expiry was NOT restored.\n' >&2
    printf '[chalkboard] Inspect %s/screen-time/state.json, then unset the expiry yourself with:\n' \
      "$STATE_DIR" >&2
    printf '[chalkboard]   chage -E -1 <child-user>\n' >&2
  fi
fi

# Disable the optional session before restoring the original SDDM configuration.
rm -f /etc/sddm.conf.d/95-chalkboard-gcompris.conf
rm -f "$STATE_DIR/gcompris-mode-enabled"

log "restoring files that existed before deployment"
# mkdir -p only, and only when the parent is genuinely absent. `install -d` with
# no -m applies 0755 to directories that already exist, which would widen
# /etc/NetworkManager/system-connections (0700, holding stored Wi-Fi PSKs) to
# world-readable and world-traversable.
while IFS= read -r backup; do
  target="/${backup#"$BACKUP_DIR/files/"}"
  parent="$(dirname "$target")"
  # -m on `mkdir -p` applies to the deepest component only, so create each level
  # explicitly to keep the intermediate ones at the default too.
  if [[ ! -d "$parent" ]]; then
    mkdir -p "$parent"
    chmod 0755 "$parent"
  fi
  cp -a "$backup" "$target"
done < <(find "$BACKUP_DIR/files" -type f ! -name '*.missing')

log "removing files that did not exist before deployment"
# backup_file also records directories, so a marker can name a directory rather
# than a file. `rm -f` fails on a directory and, under `set -e`, that would abort
# the loop and skip every remaining removal.
while IFS= read -r marker; do
  target="/${marker#"$BACKUP_DIR/files/"}"
  target="${target%.missing}"
  if [[ -d "$target" && ! -L "$target" ]]; then
    rm -rf -- "$target"
  else
    rm -f -- "$target"
  fi
done < <(find "$BACKUP_DIR/files" -type f -name '*.missing')

systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
systemctl daemon-reload
systemctl restart systemd-resolved
nmcli connection reload
restorecon -RF /etc /home/chalkboard/.config /home/chalkboard/.local 2>/dev/null || true

log "configuration rollback complete; installed applications were retained"
log "reboot to return to the previous login, power, DNS, and Plasma behavior"
