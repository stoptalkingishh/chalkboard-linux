#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=../scripts/fedora/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/lib.sh"

# Assert an expected failure and distinguish "the guard rejected the input"
# (exit 1) from "the guard never ran" (exit 2/126/127 -- a missing file makes
# bash exit 127). The `if cmd; then fail; fi` idiom conflates the two, so
# deleting a script silently disabled its own check.
expect_failure() {
  local desc="$1" expected="$2"
  shift 2
  local st=0
  "$@" >/dev/null 2>&1 || st=$?
  if [[ $st -ne $expected ]]; then
    printf 'expected exit %s from %s, got %s\n' "$expected" "$desc" "$st" >&2
    return 1
  fi
}

# pid_max is capped at 2^22, so the raw PID always renders as exactly six hex
# digits. The previous spelling, "$(printf '%06x' "$(( $$ % 16777216 )))", is a
# quoting construct that bash 5.3 mis-parses once a function definition precedes
# it, and it buys nothing.
valid_profile="$(printf '%06x' "$$")"
validate_nextdns_profile "$valid_profile"

for invalid_profile in '' ABCDEF abc12g abcde abcdef0 '../bad'; do
  # validate_nextdns_profile is a bare [[ ]] predicate, so rejection is exit 1.
  expect_failure "validate_nextdns_profile '$invalid_profile'" 1 \
    validate_nextdns_profile "$invalid_profile"
done

expect_failure 'configure-dns.sh with an invalid NextDNS ID' 1 \
  bash "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/configure-dns.sh" \
  --nextdns-profile ABCDEF

profile_file="$(mktemp)"
trap 'rm -f "$profile_file"' EXIT
printf '%s\n' ABCDEF >"$profile_file"
expect_failure 'apply-family-dns.sh with an invalid NextDNS ID' 1 \
  env CHALKBOARD_NEXTDNS_PROFILE_FILE="$profile_file" \
  bash "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/apply-family-dns.sh"
