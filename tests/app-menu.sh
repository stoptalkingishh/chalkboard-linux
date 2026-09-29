#!/usr/bin/env bash
# Behavioural tests for scripts/fedora/check-app-menu.sh, the read-only verifier
# behind verify.sh's "app menu is curated" check.
#
# Every path is injected through CHALKBOARD_* environment variables so the test
# never touches the real device. The script under test is the shipped one.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CHECKER=scripts/fedora/check-app-menu.sh
failures=0

# A scan tree is a space-separated list of directories.
ROOT_SCAN=''

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

# A fixture tree shaped like a real Fedora KDE install: the child account's
# XDG application directories, with allowlisted and non-allowlisted entries.
build_fixture() {
  local root="$1"
  rm -rf "$root"
  for d in usr/share/applications usr/local/share/applications \
           var/lib/flatpak/exports/share/applications \
           home/chalkboard/.local/share/applications; do
    mkdir -p "$root/$d"
  done
  mkdir -p "$root/etc"
  # CRLF on purpose: the checker must tolerate a checkout with CRLF endings.
  sed 's/$/\r/' config/fedora/app-allowlist.txt >"$root/etc/app-allowlist.txt"
  while IFS= read -r entry; do
    case "$entry" in
      chalkboard-*) printf x >"$root/home/chalkboard/.local/share/applications/$entry";;
    esac
  done <config/fedora/app-allowlist.txt
  printf x >"$root/usr/share/applications/org.kde.dolphin.desktop"
  local e
  for e in org.kde.konsole.desktop org.kde.discover.desktop systemsettings.desktop \
           org.mozilla.firefox.desktop org.kde.kate.desktop vivaldi-stable.desktop; do
    printf x >"$root/usr/share/applications/$e"
  done
}

write_appletsrc() {
  local path="$1" hidden="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo '[Containments][75][Applets][76][Configuration][General]'
    echo 'plugin=org.kde.plasma.kickerdash'
    # An empty $hidden is a fixture in its own right, so the conditional must
    # not be the last command in the group or `set -e` sees it as a failure.
    if [[ -n "$hidden" ]]; then
      echo "hiddenApplications=$hidden"
    fi
    return 0
  } >"$path"
}

# The checker resolves the child XDG directories from CHILD_USER, so point it at
# the fixture with a HOME-based override and chroot-free path remapping.
# Runs the checker and records its exit status in CHECK_STATUS, output in
# CHECK_OUTPUT. Using globals rather than command substitution keeps `set -e`
# from aborting the test run on an expected failure.
CHECK_STATUS=0
CHECK_OUTPUT=''
run_checker() {
  local appletrc="$1"
  CHECK_STATUS=0
  CHECK_OUTPUT=''
  set +e
  CHECK_OUTPUT=$(
    CHALKBOARD_CHILD_USER=chalkboard \
    CHALKBOARD_APPLETSRC="$appletrc" \
    CHALKBOARD_ALLOWLIST="$ROOT/etc/app-allowlist.txt" \
    CHALKBOARD_SCAN_DIRS="$ROOT_SCAN" \
    bash "$CHECKER" 2>&1
  )
  CHECK_STATUS=$?
  set -e
}

expect() {
  local label="$1" want="$2" appletrc="$3"
  run_checker "$appletrc"
  if [[ "$want" == pass && $CHECK_STATUS -eq 0 ]]; then
    printf 'PASS  %s\n' "$label"
  elif [[ "$want" == fail && $CHECK_STATUS -ne 0 ]]; then
    printf 'PASS  %s (rejected: %s)\n' "$label" \
      "$(printf '%s' "$CHECK_OUTPUT" | head -1)"
  else
    fail "$label: expected $want, got exit $CHECK_STATUS -- $CHECK_OUTPUT"
  fi
}

# The checker reads /usr/share/applications etc. directly, so exercising it
# against a fixture tree needs those paths. Rather than rewriting the script,
# verify the semantics with a copy whose scan paths are remapped, and assert the
# remap touched nothing but the path list.
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
build_fixture "$ROOT"
ROOT_SCAN="$ROOT/usr/share/applications $ROOT/usr/local/share/applications"
ROOT_SCAN+=" $ROOT/var/lib/flatpak/exports/share/applications"
ROOT_SCAN+=" $ROOT/home/chalkboard/.local/share/applications"

# Expected denylist: everything installed that is not allowlisted.
EXPECTED='org.kde.kate.desktop,org.kde.konsole.desktop,org.kde.discover.desktop,org.mozilla.firefox.desktop,systemsettings.desktop,vivaldi-stable.desktop'

write_appletsrc "$ROOT/good" "$EXPECTED"
expect 'correct curation passes' pass "$ROOT/good"

write_appletsrc "$ROOT/few" 'org.kde.konsole.desktop'
expect 'hiding only one app fails' fail "$ROOT/few"

write_appletsrc "$ROOT/nokey" ''
expect 'absent hiddenApplications key fails' fail "$ROOT/nokey"

write_appletsrc "$ROOT/backwards" \
  'chalkboard-browser.desktop,chalkboard-coolmath-games.desktop,chalkboard-cutemaze.desktop,chalkboard-gcompris.desktop,chalkboard-kcalc.desktop,chalkboard-kidpix.desktop,chalkboard-kmines.desktop,chalkboard-kolourpaint.desktop,chalkboard-ktuberling.desktop,chalkboard-writer.desktop,chalkboard-teach-your-monster.desktop'
expect 'exactly-backwards denylist fails' fail "$ROOT/backwards"

write_appletsrc "$ROOT/over" "$EXPECTED,chalkboard-writer.desktop"
expect 'hiding an allowlisted app fails' fail "$ROOT/over"

write_appletsrc "$ROOT/extra" "$EXPECTED,org.kde.spectacle.desktop"
expect 'hiding an app that is not installed fails' fail "$ROOT/extra"

: >"$ROOT/empty"
expect 'empty applet config fails' fail "$ROOT/empty"

expect 'missing applet config fails' fail "$ROOT/absent"

# Prove the fixtures are meaningful: a fixture tree with no applications at all
# must not satisfy a check that expects a non-empty denylist.
rm -f "$ROOT"/usr/share/applications/*.desktop
expect 'every app removed makes the stale denylist fail' fail "$ROOT/good"

if (( failures > 0 )); then
  printf '\napp-menu check tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'App-menu curation check tests passed.\n'
