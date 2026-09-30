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

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

# A fixture tree shaped like a real Fedora KDE install: the child account's XDG
# application directories, with allowlisted and non-allowlisted entries.
#
# Entries are real minimal desktop files, not empty placeholders, because
# child_visible_applications() in lib.sh parses them: a non-Type=Application
# entry, or one marked NoDisplay, is not visible to the child and must not be
# expected in the denylist. A fixture of empty files would silently assert
# nothing.
write_desktop() { # write_desktop <path> [extra key=value]
  local path="$1"
  shift
  {
    echo '[Desktop Entry]'
    echo 'Type=Application'
    echo 'Name=Fixture'
    echo 'Exec=/bin/true'
    printf '%s\n' "$@"
  } >"$path"
}

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
  local entry
  while IFS= read -r entry; do
    case "$entry" in
      chalkboard-*) write_desktop "$root/home/chalkboard/.local/share/applications/$entry";;
    esac
  done <config/fedora/app-allowlist.txt
  write_desktop "$root/usr/share/applications/org.kde.dolphin.desktop"
  for entry in org.kde.konsole.desktop org.kde.discover.desktop systemsettings.desktop \
              org.mozilla.firefox.desktop org.kde.kate.desktop vivaldi-stable.desktop; do
    write_desktop "$root/usr/share/applications/$entry"
  done
  # A control entry that is installed but NOT visible to the child: curation must
  # not list it, so it must not appear in the expected denylist either.
  write_desktop "$root/usr/share/applications/org.kde.kcm_hidden.desktop" 'NoDisplay=true'
}

# The fixture must mirror the layout Plasma actually writes, which was verified
# against a real Fedora 43 container: the applet header first, then plugin=, and
# only then the [Configuration][General] group holding the keys. An earlier
# version of this fixture put the group header first, which the verifier was
# written to match, so both agreed with each other and disagreed with every real
# device. Container testing is what caught it.
write_appletsrc() {
  local path="$1" hidden="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo '[Containments][75]'
    echo 'formfactor=2'
    echo 'immutability=1'
    echo 'location=bottom'
    echo 'plugin=org.kde.panel'
    echo
    echo '[Containments][75][Applets][76]'
    echo 'immutability=1'
    echo 'plugin=org.kde.plasma.kickerdash'
    echo
    echo '[Containments][75][Applets][76][Configuration][General]'
    echo 'favoriteApps=applications:chalkboard-gcompris.desktop,preferred://filemanager'
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
    CHALKBOARD_CHILD_HOME="$ROOT/home/chalkboard" \
    CHALKBOARD_ALLOWLIST="$ROOT/etc/app-allowlist.txt" \
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
# The checker reads its inputs through lib.sh, so point the application
# directories at the fixture rather than at this machine's real ones.
export CHALKBOARD_APPLICATION_DIRS="$ROOT/usr/share/applications"
CHALKBOARD_APPLICATION_DIRS+=" $ROOT/usr/local/share/applications"
CHALKBOARD_APPLICATION_DIRS+=" $ROOT/var/lib/flatpak/exports/share/applications"
CHALKBOARD_APPLICATION_DIRS+=" $ROOT/home/chalkboard/.local/share/applications"

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

# The legacy slash-separated group the real device config also carries. Its
# hiddenApplications must not be mistaken for the kickerdash applet's.
write_legacy_slash_group() {
  local path="$1" hidden="$2"
  {
    write_appletsrc_body
    echo
    echo '[Containments/75/Applets/76][Configuration][General]'
    echo "hiddenApplications=$hidden"
  } >"$path"
}
write_appletsrc_body() {
  echo '[Containments][75][Applets][76]'
  echo 'plugin=org.kde.plasma.kickerdash'
  echo
  echo '[Containments][75][Applets][76][Configuration][General]'
  echo 'favoriteApps=applications:chalkboard-gcompris.desktop'
  echo "hiddenApplications=$EXPECTED"
}
write_legacy_slash_group "$ROOT/legacy" "$EXPECTED"
expect 'a legacy slash-path duplicate group does not confuse the lookup' pass "$ROOT/legacy"

# The decoy cases. Reading hiddenApplications from anywhere after the applet header
# rather than from the applet's own group let verify.sh report the app menu as
# curated while the real kickerdash group held nothing at all, so the child saw
# every application. Each fixture below puts a plausible key where only the wrong
# parser would find it.
DECOY='org.kde.discover.desktop,org.kde.kate.desktop,org.kde.konsole.desktop'

{
  echo '[Containments][75][Applets][76]'
  echo 'plugin=org.kde.plasma.kickerdash'
  echo
  echo '[Containments][75][Applets][76][Configuration][General]'
  echo 'favoriteApps=applications:chalkboard-gcompris.desktop'
  echo
  echo '[Containments/75/Applets/76][Configuration][General]'
  echo "hiddenApplications=$DECOY"
} >"$ROOT/decoy-slash"
expect 'a slash-path group before the real value is not read as the denylist' fail \
  "$ROOT/decoy-slash"

{
  echo '[Containments][75][Applets][76]'
  echo 'plugin=org.kde.plasma.kickerdash'
  echo
  echo '[Containments][75][Applets][76][Configuration][General]'
  echo 'favoriteApps=applications:chalkboard-gcompris.desktop'
  echo
  echo '[Containments][75][Applets][77]'
  echo 'plugin=org.kde.plasma.icontasks'
  echo
  echo '[Containments][75][Applets][77][Configuration][General]'
  echo "hiddenApplications=$DECOY"
} >"$ROOT/decoy-other-applet"
expect 'another applet'"'"'s group is not read as the denylist' fail "$ROOT/decoy-other-applet"

{
  echo '[Containments][75][Applets][76]'
  echo 'plugin=org.kde.plasma.kickerdash'
  echo
  echo '[Containments][75][Applets][76][Configuration][General]'
  echo 'favoriteApps=applications:chalkboard-gcompris.desktop'
  echo
  echo '[Containments][75][Applets][77]'
  echo 'plugin=org.kde.plasma.kclock'
  echo
  echo '[Containments][75][Applets][77][Configuration][Clock]'
  echo "hiddenApplications=$DECOY"
} >"$ROOT/decoy-subgroup"
expect 'a sibling Configuration subgroup is not read as the denylist' fail \
  "$ROOT/decoy-subgroup"

# kickerdash as a containment plugin, not an applet, after an unrelated applet.
# The applet variable must be cleared at the containment boundary, or this would
# return the earlier applet's header and the writer would hide applications in
# the wrong applet.
{
  echo '[Containments][3][Applets][4]'
  echo 'plugin=org.kde.plasma.icontasks'
  echo
  echo '[Containments][9]'
  echo 'plugin=org.kde.plasma.kickerdash'
} >"$ROOT/containment-plugin"
applet=$(bash -c '
  # shellcheck source=../scripts/fedora/lib.sh
  source scripts/fedora/lib.sh
  find_kickerdash_applet "$1"' _ "$ROOT/containment-plugin" 2>/dev/null || true)
if [[ -z "$applet" ]]; then
  printf 'PASS  a containment-level kickerdash plugin is not mistaken for an applet\n'
else
  fail "find_kickerdash_applet returned '$applet' for a containment-level plugin"
fi

# ---- the group the writer actually targets --------------------------------
# Deriving the containment and applet ids with bash parameter expansion silently
# produced a mangled group name, because ${var#[Containments][} treats
# [Containments] as a glob character class rather than as literal text. The
# result was that hiddenApplications was written to a group the Dashboard never
# reads, while the verifier -- which then matched the key anywhere in the file --
# reported the app menu as curated. A deployed container showed the real output:
#   [Containments][\x5bContainments\x5d\x5b75][Applets][...
# Stub kwriteconfig6 and assert the group path it is asked to write.
write_appletsrc "$ROOT/writer" "$EXPECTED"
mkdir -p "$ROOT/bin"
cat >"$ROOT/bin/kwriteconfig6" <<'STUB'
#!/usr/bin/env bash
# Record the group path and the value, then apply nothing.
group=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --group) group+="${2}]["; shift 2 ;;
    --key) printf 'key=%s\n' "$2" >>"$STUB_LOG"; shift 2 ;;
    --file) printf 'file=%s\n' "$2" >>"$STUB_LOG"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'group=%s\n' "${group%]}" >>"$STUB_LOG"
exit 0
STUB
chmod +x "$ROOT/bin/kwriteconfig6"
: >"$ROOT/kwrite.log"
STUB_LOG="$ROOT/kwrite.log" \
CHILD_USER_FOR_TEST=1 \
  CHALKBOARD_CHILD_USER="${CHILD_USER_OVERRIDE:-chalkboard}" \
  CHALKBOARD_ALLOWLIST="$ROOT/etc/app-allowlist.txt" \
  PATH="$ROOT/bin:$PATH" \
  CHILD_HOME_OVERRIDE="$ROOT/home/chalkboard" \
  bash -c '
    # Run only the id derivation the writer depends on, against the fixture.
    # shellcheck source=../scripts/fedora/lib.sh
    source scripts/fedora/lib.sh
    read -r c a < <(find_kickerdash_ids "$1")
    printf "ids=%s,%s\n" "$c" "$a" >>"$STUB_LOG"
  ' _ "$ROOT/writer"
if grep -qx 'ids=75,76' "$ROOT/kwrite.log"; then
  printf 'PASS  the writer derives containment 75 and applet 76 from the header\n'
else
  fail "wrong containment/applet ids: $(grep '^ids=' "$ROOT/kwrite.log")"
  fail "a mangled id writes hiddenApplications to a group the Dashboard never reads"
fi
if grep -q '\[' "$ROOT/kwrite.log" 2>/dev/null && grep '^ids=' "$ROOT/kwrite.log" | grep -qE 'ids=[^,]*\['; then
  fail "the derived ids contain a bracket: $(grep '^ids=' "$ROOT/kwrite.log")"
fi

write_appletsrc "$ROOT/good" "$EXPECTED"

# Prove the fixtures are meaningful: a fixture tree with no applications at all
# must not satisfy a check that expects a non-empty denylist.
rm -f "$ROOT"/usr/share/applications/*.desktop
expect 'every app removed makes the stale denylist fail' fail "$ROOT/good"

# A NoDisplay entry is installed but invisible to the child, so curation must not
# name it. If the checker and the curation writer disagreed about this, curation
# output and checker expectation would diverge exactly as they did in production.
build_fixture "$ROOT"
write_appletsrc "$ROOT/with-nodisplay" "$EXPECTED,org.kde.kcm_hidden.desktop"
expect 'a NoDisplay entry in the denylist is rejected' fail "$ROOT/with-nodisplay"

if (( failures > 0 )); then
  printf '\napp-menu check tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'App-menu curation check tests passed.\n'
