#!/usr/bin/env bash

set -Eeuo pipefail

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config -type f -name '*.sh' -print)

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null
bash tests/dns-validation.sh
python3 -m unittest discover -s tests -p 'test_*.py'

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
  case "$desktop_file" in
    config/fedora/gcompris-session.desktop)
      # Wayland session entries legitimately use the non-standard DesktopNames
      # key; the XDG launcher validator rejects it exactly as it rejects KDE's
      # shipped plasma.desktop. Validate these entries structurally instead.
      for key in Name Comment Exec TryExec; do
        grep -Eq "^$key=.+" "$desktop_file" || {
          printf 'Incomplete wayland session entry %s: missing %s.\n' \
            "$desktop_file" "$key" >&2
          exit 1
        }
      done
      grep -Fq 'DesktopNames=' "$desktop_file" || {
        printf 'Wayland session entry %s is missing DesktopNames.\n' \
          "$desktop_file" >&2
        exit 1
      }
      grep -Fq 'Type=Application' "$desktop_file" || {
        printf 'Wayland session entry %s is missing Type.\n' \
          "$desktop_file" >&2
        exit 1
      }
      ;;
    *)
      desktop-file-validate "$desktop_file"
      ;;
  esac
done < <(find config -type f -name '*.desktop' -print)

grep -Fq 'Session=plasma.desktop' config/fedora/sddm.conf
grep -Fq 'Relogin=false' config/fedora/gcompris-sddm.conf
grep -Fq '/usr/bin/cage -s -- /usr/bin/gcompris-qt --fullscreen --enable-kioskmode' \
  scripts/fedora/gcompris-session.sh
grep -Fq 'rm -f /etc/sddm.conf.d/95-chalkboard-gcompris.conf' \
  scripts/fedora/rollback.sh

if grep -RIE '(password|passwd)[[:space:]]*=' config scripts; then
  printf 'Possible embedded password found.\n' >&2
  exit 1
fi

if grep -RIE --exclude-dir=.git '[0-9a-f]{6}\.dns\.nextdns\.io' \
    config scripts README.md; then
  printf 'Possible embedded NextDNS configuration ID found.\n' >&2
  exit 1
fi
