#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_fedora
[[ $# -eq 0 ]] || die "install-screen-time.sh does not accept arguments"

log "installing the disabled-by-default screen-time framework"
dnf -y install libnotify python3 shadow-utils systemd
install -d -o root -g root -m 0700 "$STATE_DIR" "$BACKUP_DIR" "$STATE_DIR/screen-time"

if [[ ! -e /etc/chalkboard/screen-time.conf ]]; then
  backup_file /etc/chalkboard/screen-time.conf
  install -D -o root -g root -m 0600 \
    "$REPO_ROOT/config/fedora/screen-time.conf" /etc/chalkboard/screen-time.conf
fi
# Validate the effective config before any units or binaries are installed so a
# malformed schedule cannot leave a half-installed enforcement state.
python3 "$SCRIPT_DIR/screen-time.py" check \
  || die "invalid screen-time config; fix /etc/chalkboard/screen-time.conf and rerun"

install_managed_file "$SCRIPT_DIR/screen-time.py" \
  /usr/local/libexec/chalkboard-screen-time 0755
install_managed_file "$SCRIPT_DIR/screen-time-control.sh" \
  /usr/local/sbin/chalkboard-screen-time 0755
install_managed_file "$REPO_ROOT/config/fedora/systemd/chalkboard-screen-time.service" \
  /etc/systemd/system/chalkboard-screen-time.service
install_managed_file "$REPO_ROOT/config/fedora/systemd/chalkboard-screen-time.timer" \
  /etc/systemd/system/chalkboard-screen-time.timer
install_managed_file "$REPO_ROOT/docs/screen-time.md" \
  /usr/local/share/doc/chalkboard/screen-time.md

if [[ ! -e /etc/chalkboard/screen-time.conf ]]; then
  backup_file /etc/chalkboard/screen-time.conf
  install -D -o root -g root -m 0600 \
    "$REPO_ROOT/config/fedora/screen-time.conf" /etc/chalkboard/screen-time.conf
fi

restorecon -RF /etc/chalkboard /etc/systemd/system/chalkboard-screen-time.* \
  /usr/local/libexec/chalkboard-screen-time /usr/local/sbin/chalkboard-screen-time \
  /usr/local/share/doc/chalkboard "$STATE_DIR/screen-time" 2>/dev/null || true
systemctl daemon-reload
/usr/local/libexec/chalkboard-screen-time check
if systemctl is-enabled --quiet chalkboard-screen-time.timer; then
  log "screen-time was already enabled and remains enabled"
else
  log "screen-time is installed but disabled; edit the root config, then enable it explicitly"
fi
