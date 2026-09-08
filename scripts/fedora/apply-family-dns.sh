#!/usr/bin/env bash

set -Eeuo pipefail

NEXTDNS_PROFILE_FILE="${CHALKBOARD_NEXTDNS_PROFILE_FILE:-/etc/chalkboard/nextdns-profile}"

if [[ -e "$NEXTDNS_PROFILE_FILE" ]]; then
  [[ -f "$NEXTDNS_PROFILE_FILE" && -r "$NEXTDNS_PROFILE_FILE" ]] || {
    printf 'NextDNS configuration is not a readable regular file.\n' >&2
    exit 1
  }
  nextdns_profile="$(<"$NEXTDNS_PROFILE_FILE")"
  [[ "$nextdns_profile" =~ ^[0-9a-f]{6}$ ]] || {
    printf 'Invalid NextDNS configuration ID.\n' >&2
    exit 1
  }
  dns_name="${nextdns_profile}.dns.nextdns.io"
  ipv4_dns="45.90.28.0#${dns_name} 45.90.30.0#${dns_name}"
  ipv6_dns="2a07:a8c0::#${dns_name} 2a07:a8c1::#${dns_name}"
else
  ipv4_dns='1.1.1.3#family.cloudflare-dns.com 1.0.0.3#family.cloudflare-dns.com'
  ipv6_dns='2606:4700:4700::1113#family.cloudflare-dns.com 2606:4700:4700::1003#family.cloudflare-dns.com'
fi

configure_profile() {
  local uuid="$1"
  local type

  type="$(nmcli -g connection.type connection show "$uuid")"
  case "$type" in
    802-11-wireless|802-3-ethernet)
      ;;
    *)
      return
      ;;
  esac

  nmcli connection modify "$uuid" \
    ipv4.ignore-auto-dns yes \
    ipv6.ignore-auto-dns yes \
    ipv4.dns-priority -2147483648 \
    ipv6.dns-priority -2147483648 \
    ipv4.dns-search '~.' \
    ipv6.dns-search '~.' \
    ipv4.dns "$ipv4_dns" \
    ipv6.dns "$ipv6_dns"
}

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root.\n' >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  configure_profile "$1"
else
  while IFS=: read -r uuid type; do
    case "$type" in
      802-11-wireless|802-3-ethernet)
        configure_profile "$uuid"
        ;;
    esac
  done < <(nmcli -t -f UUID,TYPE connection show)
fi

while IFS=: read -r uuid device; do
  if [[ $# -eq 0 || "$uuid" == "$1" ]]; then
    nmcli device reapply "$device" >/dev/null 2>&1 || true
  fi
done < <(nmcli -t -f UUID,DEVICE connection show --active)

if [[ $# -eq 0 ]]; then
  systemctl restart systemd-resolved
fi
