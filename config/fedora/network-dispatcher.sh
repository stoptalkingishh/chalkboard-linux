#!/usr/bin/env bash

set -Eeuo pipefail

case "${2:-}" in
  up|dhcp4-change|dhcp6-change)
    if [[ -n "${CONNECTION_UUID:-}" ]]; then
      /usr/local/sbin/chalkboard-family-dns "$CONNECTION_UUID"
    fi
    ;;
esac
