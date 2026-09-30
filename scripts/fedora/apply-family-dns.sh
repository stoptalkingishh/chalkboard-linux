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
  local ipv6_method

  type="$(nmcli -g connection.type connection show "$uuid")"
  case "$type" in
    802-11-wireless|802-3-ethernet)
      ;;
    *)
      return
      ;;
  esac

  # NetworkManager rejects ipv6.dns and the other ipv6 resolver properties unless
  # the connection's ipv6.method can carry them. Measured against NetworkManager
  # on Fedora 43, which accepts ipv6 settings for:
  #
  #   auto, dhcp, shared
  #
  # and rejects them for:
  #
  #   manual, ignore, link-local, disabled
  #
  # This is a positive list rather than a check for "disabled", because the
  # rejecting set is larger than one value and a parent who configures IPv6 by
  # hand gets method=manual.
  #
  # nmcli applies a modify atomically, so a rejected property discards the others.
  # Setting both families in one call therefore left the connection with no
  # filtering at all, and because the dispatcher runs on every activation and
  # NetworkManager ignores its exit status, that failure was silent and
  # repeatable. Apply the families separately so IPv4 filtering always lands, and
  # leave IPv6 alone when NetworkManager would refuse rather than changing the
  # parent's IPv6 configuration to get filtering onto it.
  ipv6_method="$(nmcli -g ipv6.method connection show "$uuid" 2>/dev/null || printf '')"

  nmcli connection modify "$uuid" \
    ipv4.ignore-auto-dns yes \
    ipv4.dns-priority -2147483648 \
    ipv4.dns-search '~.' \
    ipv4.dns "$ipv4_dns"

  case "$ipv6_method" in
    auto|dhcp|shared)
      nmcli connection modify "$uuid" \
        ipv6.ignore-auto-dns yes \
        ipv6.dns-priority -2147483648 \
        ipv6.dns-search '~.' \
        ipv6.dns "$ipv6_dns"
      ;;
    *)
      printf 'IPv6 method %s on connection %s cannot carry filtered IPv6 resolvers; applied IPv4 filtering only.\n' \
        "${ipv6_method:-<unset>}" "$uuid" >&2
      ;;
  esac
}

if [[ $EUID -ne 0 && -z "${CHALKBOARD_FAKE_ROOT:-}" ]]; then
  printf 'Run this script as root.\n' >&2
  exit 1
fi

# Configure every connection, then report the ones that could not be configured.
# Aborting on the first failure meant a single connection that NetworkManager
# rejected left every later connection with an unfiltered resolver, which is the
# same failure this script exists to prevent.
failed=0
if [[ $# -gt 0 ]]; then
  configure_profile "$1" || failed=$((failed + 1))
else
  while IFS=: read -r uuid type; do
    case "$type" in
      802-11-wireless|802-3-ethernet)
        configure_profile "$uuid" || failed=$((failed + 1))
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

if (( failed > 0 )); then
  printf 'failed to apply filtered DNS to %s connection(s)\n' "$failed" >&2
  exit 1
fi
