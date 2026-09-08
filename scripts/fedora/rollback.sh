#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
[[ -d "$BACKUP_DIR/files" ]] || die "no Chalkboard backup was found"

# Disable the optional session before restoring the original SDDM configuration.
rm -f /etc/sddm.conf.d/95-chalkboard-gcompris.conf
rm -f "$STATE_DIR/gcompris-mode-enabled"

log "restoring files that existed before deployment"
while IFS= read -r backup; do
  target="/${backup#"$BACKUP_DIR/files/"}"
  install -d "$(dirname "$target")"
  cp -a "$backup" "$target"
done < <(find "$BACKUP_DIR/files" -type f ! -name '*.missing')

log "removing files that did not exist before deployment"
while IFS= read -r marker; do
  target="/${marker#"$BACKUP_DIR/files/"}"
  target="${target%.missing}"
  rm -f "$target"
done < <(find "$BACKUP_DIR/files" -type f -name '*.missing')

systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
systemctl daemon-reload
systemctl restart systemd-resolved
nmcli connection reload
restorecon -RF /etc /home/chalkboard/.config /home/chalkboard/.local 2>/dev/null || true

log "configuration rollback complete; installed applications were retained"
log "reboot to return to the previous login, power, DNS, and Plasma behavior"
