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

# ---- nmcli interaction, exercised against a stub ---------------------------
# NetworkManager rejects ipv6.dns on a connection whose IPv6 method is disabled,
# and it applies a modify atomically, so the original single call set both
# families together and a rejection discarded the IPv4 filtering too. Because the
# dispatcher runs on every activation and NetworkManager ignores its exit status,
# the connection ended up with no filtering and no error anyone saw. Recorded
# here with a stub rather than a live NetworkManager so it runs in CI.
APPLY="$(dirname -- "${BASH_SOURCE[0]}")/../scripts/fedora/apply-family-dns.sh"
STUB_DIR="$(mktemp -d)"
stub_log="$STUB_DIR/nmcli.log"
cat >"$STUB_DIR/nmcli" <<'STUB'
#!/usr/bin/env bash
# Stub NetworkManager. Model the real behaviour that matters here: a modify is
# applied atomically, and ipv6.dns and friends are rejected outright on a
# connection whose ipv6.method is disabled.
uuid='test-uuid'
# The stub must actually reproduce the rejection, or the test proves nothing.
[[ "${NMCLI_IPV6_METHOD:-auto}" == disabled ]] && method=1 || method=0
if [[ "${1:-}" == '-g' ]]; then
  # A property query: nmcli -g <property> connection show <uuid>
  case "${2:-}" in
    connection.type) printf '802-3-ethernet\n' ;;
    ipv6.method)
      if [[ "${NMCLI_IPV6_METHOD:-auto}" == disabled ]]; then printf 'disabled\n'
      else printf 'auto\n'; fi
      ;;
    *) printf '\n' ;;
  esac
  exit 0
fi
[[ "${1:-}" == 'connection' && "${2:-}" == 'modify' ]] || {
  case "$*" in
    *device*) exit 0 ;;
    *) printf '%s:802-3-ethernet\n' "$uuid" ;;
  esac
}
shift 2
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[i]}" in
    ipv6.dns|ipv6.dns-search|ipv6.dns-priority|ipv6.ignore-auto-dns)
      if (( method )); then
        echo "Error: Failed to modify connection '$uuid': ${args[i]}: this property is not allowed for 'method=disabled'" >&2
        exit 1
      fi
      ;;
  esac
done
printf 'modify %s\n' "${args[*]}" >>"$NMCLI_LOG"
exit 0
STUB
chmod +x "$STUB_DIR/nmcli"
# apply-family-dns.sh restarts systemd-resolved when run with no profile
# argument. Stub it: the test must not touch the developer's or CI machine.
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_DIR/systemctl"
chmod +x "$STUB_DIR/systemctl"

run_apply() { # run_apply <ipv6-method> ; sets APPLY_OUT
  # apply-family-dns.sh requires root. It needs nothing else from the system, so
  # exercise it under a fakeroot-style stub rather than requiring the test suite
  # to be run as root, which would make an ordinary developer run differ from CI.
  APPLY_OUT=$(NMCLI_LOG="$stub_log" NMCLI_IPV6_METHOD="$1" \
    CHALKBOARD_FAKE_ROOT=1 PATH="$STUB_DIR:$PATH" bash "$APPLY" 2>&1) || return 1
}

: >"$stub_log"
if run_apply disabled; then
  : # the IPv4 half must succeed; the IPv6 half is skipped
else
  printf 'apply-family-dns.sh failed outright on an IPv6-disabled connection: %s\n' \
    "$APPLY_OUT" >&2
  exit 1
fi

if grep -q 'ipv4.dns ' "$stub_log"; then
  printf 'IPv4 filtering is applied on an IPv6-disabled connection\n'
else
  printf 'IPv4 filtering was NOT applied on an IPv6-disabled connection: %s\n' \
    "$APPLY_OUT" >&2
  exit 1
fi

if grep -q 'ipv6.dns ' "$stub_log"; then
  printf 'IPv6 properties were set despite ipv6.method=disabled\n' >&2
  exit 1
else
  printf 'IPv6 properties are skipped when IPv6 is disabled\n'
fi

if [[ "$APPLY_OUT" == *"IPv6 is disabled"* ]]; then
  printf 'the skip is reported rather than silent\n'
else
  printf 'skipping IPv6 was not reported: %s\n' "$APPLY_OUT" >&2
  exit 1
fi

: >"$stub_log"
if run_apply auto; then
  if grep -q 'ipv6.dns ' "$stub_log" && grep -q 'ipv4.dns ' "$stub_log"; then
    printf 'both families are configured when IPv6 is enabled\n'
  else
    printf 'both families were not configured when IPv6 is enabled\n' >&2
    exit 1
  fi
else
  printf 'apply-family-dns.sh failed with IPv6 enabled: %s\n' "$APPLY_OUT" >&2
  exit 1
fi

rm -rf "$STUB_DIR"
