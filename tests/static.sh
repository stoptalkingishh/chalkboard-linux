#!/usr/bin/env bash

set -Eeuo pipefail

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config -type f -name '*.sh' -print)

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null

grep -Fq 'const weatherType = "org.kde.plasma.weather"' config/fedora/kde/weather.js
grep -Fq 'widget.readConfig("Managed", "false")' config/fedora/kde/weather.js
grep -Fq 'if (!enabled)' config/fedora/kde/weather.js
if grep -Eq '^Location=.+|noaa\|weather\|[^" +]' config/fedora/kde/weather.js config/fedora/weather-autostart.desktop; then
  printf 'Weather assets must not contain a configured location.\n' >&2
  exit 1
fi
bash scripts/fedora/weather.sh --help >/dev/null
if bash scripts/fedora/weather.sh enable --provider noaa >/dev/null 2>&1; then
  printf 'Weather enable accepted a missing location.\n' >&2
  exit 1
fi
node tests/weather.js

while IFS= read -r desktop_file; do
  desktop-file-validate "$desktop_file"
done < <(find config -type f -name '*.desktop' -print)

if grep -RIE '(password|passwd)[[:space:]]*=' config scripts; then
  printf 'Possible embedded password found.\n' >&2
  exit 1
fi
