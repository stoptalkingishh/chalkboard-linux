#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXTDNS_PROFILE_FILE="/etc/chalkboard/nextdns-profile"
nextdns_profile=""

case $# in
  0)
    ;;
  2)
    [[ "$1" == --nextdns-profile ]] || die "usage: configure-dns.sh [--nextdns-profile CONFIGURATION_ID]"
    validate_nextdns_profile "$2" || die "NextDNS configuration ID must be exactly six lowercase hexadecimal characters"
    nextdns_profile="$2"
    ;;
  *)
    die "usage: configure-dns.sh [--nextdns-profile CONFIGURATION_ID]"
    ;;
esac

require_root
require_fedora
install -d -o root -g root -m 0700 "$STATE_DIR" "$BACKUP_DIR" /etc/chalkboard

log "backing up DNS configuration and NetworkManager profiles"
backup_file /etc/NetworkManager/system-connections
backup_file "$NEXTDNS_PROFILE_FILE"

install_managed_file "$SCRIPT_DIR/apply-family-dns.sh" \
  /usr/local/sbin/chalkboard-family-dns 0755
install_managed_file "$REPO_ROOT/config/fedora/network-dispatcher.sh" \
  /etc/NetworkManager/dispatcher.d/90-chalkboard-family-dns 0755

if [[ -n "$nextdns_profile" ]]; then
  log "configuring parent-supplied NextDNS profile"
  install_managed_file "$REPO_ROOT/config/fedora/systemd-resolved-nextdns.conf" \
    /etc/systemd/resolved.conf.d/60-chalkboard-family.conf
  profile_temp="$(mktemp /etc/chalkboard/.nextdns-profile.XXXXXX)"
  trap 'rm -f "$profile_temp"' EXIT
  printf '%s\n' "$nextdns_profile" >"$profile_temp"
  chmod 0600 "$profile_temp"
  mv -f "$profile_temp" "$NEXTDNS_PROFILE_FILE"
  trap - EXIT
else
  log "configuring default Cloudflare Family DNS"
  install_managed_file "$REPO_ROOT/config/fedora/systemd-resolved.conf" \
    /etc/systemd/resolved.conf.d/60-chalkboard-family.conf
  # Keep foreign or previous profiles instead of deleting operator data; the
  # handover file remains absent so NextDNS stays disabled until it is enabled.
  if [[ -e "$NEXTDNS_PROFILE_FILE" ]]; then
    mv -f "$NEXTDNS_PROFILE_FILE" \
      "$NEXTDNS_PROFILE_FILE.disabled-$(date -u +%Y%m%dT%H%M%SZ)" || true
  fi
fi

bash "$SCRIPT_DIR/apply-family-dns.sh"
restorecon -RF /etc/chalkboard /etc/systemd/resolved.conf.d \
  /etc/NetworkManager/dispatcher.d /usr/local/sbin/chalkboard-family-dns \
  2>/dev/null || true
