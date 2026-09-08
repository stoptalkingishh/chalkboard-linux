#!/usr/bin/env bash

set -Eeuo pipefail

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config -type f -name '*.sh' -print)

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null
bash tests/dns-validation.sh

while IFS= read -r desktop_file; do
  desktop-file-validate "$desktop_file"
done < <(find config -type f -name '*.desktop' -print)

if grep -RIE '(password|passwd)[[:space:]]*=' config scripts; then
  printf 'Possible embedded password found.\n' >&2
  exit 1
fi

if grep -RIE --exclude-dir=.git '[0-9a-f]{6}\.dns\.nextdns\.io' \
    config scripts README.md; then
  printf 'Possible embedded NextDNS configuration ID found.\n' >&2
  exit 1
fi
