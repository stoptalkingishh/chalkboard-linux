#!/usr/bin/env bash

set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { printf 'Run as root, for example with sudo.\n' >&2; exit 1; }
[[ $# -eq 1 ]] || { printf 'Usage: %s {enable|disable|force-disable|status|check}\n' "$0" >&2; exit 2; }

case "$1" in
  enable)
    /usr/local/libexec/chalkboard-screen-time check
    systemctl enable --now chalkboard-screen-time.timer || true
    if ! /usr/local/libexec/chalkboard-screen-time enforce; then
      printf 'chalkboard: enforcement reported a problem; the timer remains enabled and will retry.\n' >&2
      exit 1
    fi
    printf 'Screen-time enforcement is enabled.\n'
    ;;
  disable)
    systemctl disable --now chalkboard-screen-time.timer 2>/dev/null || true
    if ! /usr/local/libexec/chalkboard-screen-time release; then
      printf 'chalkboard: release reported a problem; investigate before using force-disable.\n' >&2
      exit 1
    fi
    printf 'Screen-time enforcement is disabled.\n'
    ;;
  force-disable)
    systemctl disable --now chalkboard-screen-time.timer 2>/dev/null || true
    if ! /usr/local/libexec/chalkboard-screen-time force-release; then
      printf 'chalkboard: force-release failed.\n' >&2
      exit 1
    fi
    printf 'Screen-time enforcement is disabled and the saved account expiry was restored.\n'
    ;;
  status)
    systemctl is-enabled chalkboard-screen-time.timer 2>/dev/null || true
    systemctl is-active chalkboard-screen-time.timer 2>/dev/null || true
    /usr/local/libexec/chalkboard-screen-time status
    ;;
  check)
    /usr/local/libexec/chalkboard-screen-time check
    ;;
  *)
    printf 'Usage: %s {enable|disable|force-disable|status|check}\n' "$0" >&2
    exit 2
    ;;
esac
