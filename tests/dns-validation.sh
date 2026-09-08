#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=../scripts/fedora/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/lib.sh"

valid_profile="$(printf '%06x' "$(( $$ % 16777216 ))")"
validate_nextdns_profile "$valid_profile"

for invalid_profile in '' ABCDEF abc12g abcde abcdef0 '../bad'; do
  if validate_nextdns_profile "$invalid_profile"; then
    printf 'Accepted invalid NextDNS configuration ID: %s\n' "$invalid_profile" >&2
    exit 1
  fi
done

if bash "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/configure-dns.sh" \
  --nextdns-profile ABCDEF >/dev/null 2>&1; then
  printf 'DNS configuration accepted an invalid NextDNS ID.\n' >&2
  exit 1
fi

profile_file="$(mktemp)"
trap 'rm -f "$profile_file"' EXIT
printf '%s\n' ABCDEF >"$profile_file"
if CHALKBOARD_NEXTDNS_PROFILE_FILE="$profile_file" \
  bash "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/apply-family-dns.sh" \
  >/dev/null 2>&1; then
  printf 'DNS applicator accepted an invalid NextDNS ID.\n' >&2
  exit 1
fi
