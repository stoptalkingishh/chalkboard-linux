#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log() {
  printf '[chalkboard] %s\n' "$*"
}

# Assert that a command fails, and that it fails for the *right* reason.
# The `if cmd; then fail; fi` idiom cannot tell exit 1 (the guard worked) from
# exit 2/126/127 (grep hit a missing file, bash hit a missing script), so
# deleting the script under test silently disabled its own check and the suite
# still reported success. Every "must fail" guard goes through here.
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

# grep-flavored sibling of expect_failure: exit 1 means "clean, no match",
# which is the only acceptable outcome. Output is kept on stderr so the
# offending line is visible when the check does trip.
expect_no_match() {
  local desc="$1"
  shift
  local st=0
  "$@" >&2 || st=$?
  if [[ $st -ne 1 ]]; then
    printf 'expected no match for %s, got exit %s\n' "$desc" "$st" >&2
    return 1
  fi
}

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config tests -type f -name '*.sh' -print)

bash tests/retro-lib.sh
bash tests/launchers.sh
bash tests/app-menu.sh
bash tests/rollback.sh

# panel.js is handed verbatim to PlasmaShell.evaluateScript, so a syntax error
# there does not fail loudly -- it yields an empty child panel. weather.js is
# evaluated the same way. screen-time.py is a top-level script, not imported, so
# nothing else in the tree ever parses it.
node --check config/fedora/kde/panel.js
node --check config/fedora/kde/weather.js
# Compile to a throwaway path: the plain `py_compile` module writes a __pycache__
# entry, which fails on a read-only checkout and leaves an artifact otherwise.
compile_tmp="$(mktemp -d)"
trap 'rm -rf "$compile_tmp"' EXIT
python3 -c '
import py_compile, sys
py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)
' scripts/fedora/screen-time.py "$compile_tmp/screen-time.pyc"

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null
bash tests/dns-validation.sh
python3 -m unittest discover -s tests -p 'test_*.py'

grep -Fq 'const weatherType = "org.kde.plasma.weather"' config/fedora/kde/weather.js
grep -Fq 'widget.readConfig("Managed", "false")' config/fedora/kde/weather.js
grep -Fq 'if (!enabled)' config/fedora/kde/weather.js

# Match the *shape* of a configured location, not a fixed INI prefix. The old
# `^Location=.+` pattern missed an indented `  Location=X`, `Location = X`, a
# JS object literal `Location: "X"`, and a concatenated `"noaa|weather|" + CITY`
# -- i.e. every form that is actually realistic.
LOCATION_LEAK_PATTERN=$'(^|[^A-Za-z])Location[[:space:]]*=[^=]|noaa\\|weather\\|[A-Za-z0-9]|["\']noaa\\|weather\\||Location:[[:space:]]*"'
# Desktop-entry keys are case-sensitive and weather-autostart.desktop declares
# no location key at all, so any case variant there is a leak. Scoped away from
# weather.js, which legitimately assigns `const location = String(...)`.
INI_LOCATION_PATTERN='^[[:space:]]*[Ll]ocation[[:space:]]*='

# Self-test. If these patterns ever stop detecting the shapes they were written
# for, every scan below passes vacuously, so prove they still bite first and
# name the case that rotted.
leak_case_detected() {
  printf '%s\n' "$1" | grep -Eq "$LOCATION_LEAK_PATTERN" ||
    printf '%s\n' "$1" | grep -Eq "$INI_LOCATION_PATTERN"
}

for known_bad in \
  '  Location=Denver' \
  'Location = Denver' \
  'Location: "Denver"' \
  '"noaa|weather|" + CITY' \
  'location=Denver'; do
  if ! leak_case_detected "$known_bad"; then
    printf 'Location-leak pattern failed its self-test: it no longer detects %s\n' \
      "$known_bad" >&2
    exit 1
  fi
done

for known_good in \
  'const location = String(config.readEntry("Location"));' \
  'if (provider !== "noaa" || !location || location.includes("|")) {' \
  'weather.writeConfig("source", provider + "|weather|" + location);'; do
  if leak_case_detected "$known_good"; then
    printf 'Location-leak pattern is over-broad: it flags legitimate code %s\n' \
      "$known_good" >&2
    exit 1
  fi
done

expect_no_match 'configured location in weather.js / weather-autostart.desktop' \
  grep -En "$LOCATION_LEAK_PATTERN" \
  config/fedora/kde/weather.js config/fedora/weather-autostart.desktop
expect_no_match 'location key in weather-autostart.desktop' \
  grep -Ein "$INI_LOCATION_PATTERN" config/fedora/weather-autostart.desktop

bash scripts/fedora/weather.sh --help >/dev/null
expect_failure 'weather.sh enable with no location' 1 \
  bash scripts/fedora/weather.sh enable --provider noaa
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
        printf 'Wayland session entry %s is missing Type.\n' "$desktop_file" >&2
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

expect_no_match 'embedded password' \
  grep -RIE '(password|passwd)[[:space:]]*=' config scripts

expect_no_match 'embedded NextDNS configuration ID' \
  grep -RIE --exclude-dir=.git '[0-9a-f]{6}\.dns\.nextdns\.io' \
  config scripts README.md

# Reject executable automation only. The separator-tolerant pattern covers
# "scratchjr", "Scratch Jr", "scratch-jr", and "scratch_jr". Documentation and
# future re-verification text belong in docs/ or tests/, which are not scanned.
# When all ScratchJr acceptance criteria pass, this check must be removed along
# with the launcher addition.
expect_no_match 'ScratchJr executable automation' \
  grep -RIEi 'scratch[ _-]?jr' config scripts

log 'static checks passed'
