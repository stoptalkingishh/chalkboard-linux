#!/usr/bin/env bash

set -Eeuo pipefail

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config -type f -name '*.sh' -print)

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null
python3 -m unittest discover -s tests -p 'test_*.py'

while IFS= read -r desktop_file; do
  desktop-file-validate "$desktop_file"
done < <(find config -type f -name '*.desktop' -print)

if grep -RIE '(password|passwd)[[:space:]]*=' config scripts; then
  printf 'Possible embedded password found.\n' >&2
  exit 1
fi
