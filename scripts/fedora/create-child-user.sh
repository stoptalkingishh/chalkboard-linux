#!/usr/bin/env bash

set -Eeuo pipefail

dry_run=false
username="chalkboard"

usage() {
  cat <<'EOF'
Usage: create-child-user.sh [--dry-run] [username]

Create an unprivileged Fedora child account with a locked password.
EOF
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'

  if [[ "$dry_run" == false ]]; then
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      username="$1"
      ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root, for example with sudo.\n' >&2
  exit 1
fi

if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  printf 'Invalid username: %s\n' "$username" >&2
  exit 2
fi

if [[ "$username" == root ]]; then
  printf 'Refusing to alter the root account.\n' >&2
  exit 2
fi

if getent passwd "$username" >/dev/null; then
  uid="$(id -u "$username")"
  if (( uid < 1000 )); then
    printf 'Refusing to alter system account %s with UID %s.\n' "$username" "$uid" >&2
    exit 1
  fi
  printf 'Account %s already exists; enforcing child-account policy.\n' "$username"
else
  run useradd --create-home --shell /bin/bash --comment "Chalkboard child account" "$username"
fi

for admin_group in wheel sudo; do
  if getent group "$admin_group" >/dev/null && id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$admin_group"; then
    run gpasswd --delete "$username" "$admin_group"
  fi
done

run usermod --lock "$username"

if [[ "$dry_run" == true ]]; then
  printf 'Dry run complete; no changes were made.\n'
  exit 0
fi

printf '\nAccount verification:\n'
getent passwd "$username"
id "$username"
passwd --status "$username"

if id -nG "$username" | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'; then
  printf 'Account still belongs to an administrative group.\n' >&2
  exit 1
fi

printf 'Child account %s is present, non-admin, and password-locked.\n' "$username"
