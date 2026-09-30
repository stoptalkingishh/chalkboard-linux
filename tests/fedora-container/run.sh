#!/usr/bin/env bash

# The [$i] markers in the KConfig fixtures are literal syntax: KConfig treats
# them as a marker, so the shell must not expand them.
# shellcheck disable=SC2016
# Container integration test for the app-menu curation and its verifier.
#
# This runs the SHIPPED scripts/fedora/curate-app-menu.sh and
# scripts/fedora/check-app-menu.sh inside a real Fedora 43 root filesystem,
# against the real desktop file database that the packages in the Dockerfile
# produce, and against a real unprivileged account named chalkboard.
#
# Why this cannot be done in the fixture-based tests/app-menu.sh: the fixtures
# invent a desktop file set. The bug that motivated check-app-menu.sh was a check
# calibrated against a number of installed applications, so the thing worth
# testing is what Fedora actually ships.
#
# Requires root inside the container. See README.md for what it does not cover.
set -Eeuo pipefail

REPO="${REPO:-/repo}"
CHILD_USER=chalkboard
CHILD_UID=1001
CHILD_HOME=/home/chalkboard
ALLOWLIST_SRC="$REPO/config/fedora/app-allowlist.txt"
ALLOWLIST_DST=/usr/local/share/chalkboard/app-allowlist.txt
APPLETSRC="$CHILD_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

failures=0
fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}
pass() { printf 'PASS  %s\n' "$*"; }

# ---- environment assertions -------------------------------------------------
# lib.sh's require_fedora gates on VERSION_ID 43, so confirm the image really is
# the target release rather than trusting the tag.
# shellcheck source=../../scripts/fedora/lib.sh
source "$REPO/scripts/fedora/lib.sh"
if require_fedora 2>/dev/null; then
  pass "container is Fedora 43, as lib.sh requires"
else
  fail "container is not Fedora 43: $(. /etc/os-release; echo "$PRETTY_NAME")"
fi

installed=$(find /usr/share/applications /usr/local/share/applications \
  -maxdepth 1 -type f -name '*.desktop' 2>/dev/null | wc -l)
printf 'info  %s .desktop files installed by the package set\n' "$installed"
if (( installed < 60 )); then
  fail "only $installed application entries present; the KDE package set looks incomplete, so denylist assertions would be vacuous"
else
  pass "a realistically large application set is present ($installed entries)"
fi

# ---- build the child account and its launcher directory ---------------------
if ! id "$CHILD_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --uid "$CHILD_UID" "$CHILD_USER"
fi
install -d -o "$CHILD_USER" -g "$CHILD_USER" -m 0700 \
  "$CHILD_HOME/.config" \
  "$CHILD_HOME/.local/share/applications"

# deploy.sh installs every launcher into the child's own application directory.
install -o "$CHILD_USER" -g "$CHILD_USER" -m 0644 \
  "$REPO"/config/fedora/launchers/*.desktop \
  "$CHILD_HOME/.local/share/applications/"

install -d -m 0755 /usr/local/share/chalkboard
install -m 0644 "$ALLOWLIST_SRC" "$ALLOWLIST_DST"

# The curated menu entry is a static snapshot, so start from a valid kickerdash
# applet with no hiddenApplications key, which is what first-login.sh produces.
cat >"$APPLETSRC" <<'APPL'
[Containments][75]
formfactor=2
immutability=1
location=bottom
plugin=org.kde.panel

[Containments][75][Applets][76]
immutability=1
plugin=org.kde.plasma.kickerdash

[Containments][75][Applets][76][Configuration][General]
favoriteApps=applications:chalkboard-gcompris.desktop,preferred://filemanager
APPL
chown "$CHILD_USER:$CHILD_USER" "$APPLETSRC"
chmod 0600 "$APPLETSRC"

# ---- 1. curation must hide every non-allowlisted application ----------------
bash "$REPO/scripts/fedora/curate-app-menu.sh" "$CHILD_USER"

hidden_count=$(grep -c '^hiddenApplications=' "$APPLETSRC" || true)
if [[ "$hidden_count" == 1 ]]; then
  pass "curation wrote exactly one hiddenApplications key"
else
  fail "expected 1 hiddenApplications key, found $hidden_count"
fi

# ---- 2. the verifier must agree with the curation it just checked ------------
if bash "$REPO/scripts/fedora/check-app-menu.sh"; then
  pass "check-app-menu.sh accepts the curation curate-app-menu.sh just produced"
else
  fail "check-app-menu.sh rejected curation produced by curate-app-menu.sh"
fi

# ---- 3. the specific apps that matter must be hidden ------------------------
# These are the ones the project exists to keep out of the child's menu. A check
# that merely counted entries would not notice their absence. Only apps the
# container actually installed are asserted: asserting on an absent package would
# make this test lie about what it verified.
hidden_list=$(grep '^hiddenApplications=' "$APPLETSRC" | cut -d= -f2-)
for id in org.kde.konsole.desktop systemsettings.desktop org.kde.kate.desktop \
          org.kde.kwrite.desktop org.kde.dolphin.desktop; do
  if [[ ! -f "/usr/share/applications/$id" ]]; then
    printf 'skip  %s is not installed in this container image\n' "$id"
    continue
  fi
  if [[ ",$hidden_list," == *",$id,"* ]]; then
    pass "curation hides $id"
  else
    fail "curation does NOT hide $id"
  fi
done

# ---- 4. allowlisted apps must NOT be hidden ---------------------------------
# The old check could not detect this: a denylist naming exactly the allowlisted
# entries had the same length as a correct one.
for id in chalkboard-gcompris.desktop chalkboard-kcalc.desktop \
          chalkboard-kmines.desktop chalkboard-writer.desktop \
          org.kde.dolphin.desktop; do
  if [[ ",$hidden_list," == *",$id,"* ]]; then
    fail "curation hides the allowlisted application $id"
  else
    pass "curation leaves the allowlisted application $id visible"
  fi
done

# ---- 5. the verifier must reject a tampered denylist ------------------------
# Reintroduce the class of failure the threshold check accepted.
tamper_add() { # add an id to the denylist
  cp "$APPLETSRC" "$APPLETSRC.bak"
  sed -i "s/^hiddenApplications=/hiddenApplications=$1,/" "$APPLETSRC"
}
tamper_remove() { # remove an id from the denylist, re-exposing it to the child
  cp "$APPLETSRC" "$APPLETSRC.bak"
  sed -i "/^hiddenApplications=/ s/\<$1\>,\?//" "$APPLETSRC"
}
restore() { mv -f "$APPLETSRC.bak" "$APPLETSRC"; chown "$CHILD_USER:$CHILD_USER" "$APPLETSRC"; }

# Re-exposing Konsole: the single most important entry in the denylist.
tamper_remove org.kde.konsole.desktop
if bash "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1; then
  fail "check-app-menu.sh accepted a denylist that re-exposes Konsole"
else
  pass "check-app-menu.sh rejects a denylist that re-exposes Konsole"
fi
restore

# An allowlisted app hidden: curation would strand the child with no route to a
# launcher this project deliberately ships.
tamper_add chalkboard-writer.desktop
if bash "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1; then
  fail "check-app-menu.sh accepted a denylist that hides an allowlisted app"
else
  pass "check-app-menu.sh rejects a denylist that hides an allowlisted app"
fi
restore

# An entry that is not installed at all, which curation never writes.
tamper_add org.kde.nonexistent-app.desktop
if bash "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1; then
  fail "check-app-menu.sh accepted a denylist naming an application that is not installed"
else
  pass "check-app-menu.sh rejects a denylist naming an application that is not installed"
fi
restore

# A NoDisplay entry is installed but invisible to the child, so curation must
# never name it. Most KDE control-centre modules are NoDisplay, which is exactly
# the class of entry a "hide everything installed" implementation gets wrong, and
# exactly what this test caught the verifier getting wrong.
tamper_add kcm_about.desktop
if bash "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1; then
  fail "check-app-menu.sh accepted a NoDisplay entry in the denylist"
else
  pass "check-app-menu.sh rejects a NoDisplay entry in the denylist"
fi
restore

# ---- 6. the verifier must fail closed on a missing applet config -------------
mv -f "$APPLETSRC" "$APPLETSRC.hidden"
if bash "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1; then
  fail "check-app-menu.sh passed with no applet config at all"
else
  pass "check-app-menu.sh fails closed when the applet config is absent"
fi
mv -f "$APPLETSRC.hidden" "$APPLETSRC"
chown "$CHILD_USER:$CHILD_USER" "$APPLETSRC"

# ---- 7. curation is idempotent ----------------------------------------------
before=$(grep '^hiddenApplications=' "$APPLETSRC")
bash "$REPO/scripts/fedora/curate-app-menu.sh" "$CHILD_USER" >/dev/null
after=$(grep '^hiddenApplications=' "$APPLETSRC")
if [[ "$before" == "$after" ]]; then
  pass "re-running curation is idempotent"
else
  fail "re-running curation changed the denylist"
fi

# ---- 8. the applet lookup must stay portable awk ---------------------------
# The curation script originally located the kickerdash applet with the
# three-argument match(), a GNU awk extension. Fedora ships gawk so the device
# was never at risk, but it made the script the one thing in the repo that could
# not run on a stock Debian or Ubuntu CI image. lib.sh now does the lookup with
# plain string comparison, so guard against a regression.
if grep -REq 'match\(.*,.*,.*\)' "$REPO/scripts/fedora/"; then
  fail "a script uses the three-argument awk match(), a GNU awk extension: $(grep -RlE 'match\(.*,.*,.*\)' "$REPO/scripts/fedora/" | tr '\n' ' ')"
else
  pass "the applet lookup uses no GNU awk extension"
fi

# Confirm the lookup works here rather than trusting the absence of a pattern.
if [[ -n "$(find_kickerdash_applet "$APPLETSRC")" ]]; then
  pass "find_kickerdash_applet locates the applet in this container"
else
  fail "find_kickerdash_applet did not locate the kickerdash applet"
fi

# ---- 9. installed helpers must work from their installed paths --------------
# deploy.sh installs these under renamed paths, so $SCRIPT_DIR no longer points
# at a directory holding lib.sh. check-app-menu.sh failed on a freshly deployed
# device for exactly that reason: it sourced "$SCRIPT_DIR/lib.sh", which does not
# exist at /usr/local/libexec/lib.sh, so finalize-lockdown.sh aborted before it
# could write the finalized marker and verify.sh reported two failures. The
# fixture-based tests could not catch it because they run the scripts from the
# repository, where lib.sh is a neighbour.
mkdir -p /usr/local/libexec
install -m 0755 "$REPO/scripts/fedora/lib.sh" /usr/local/libexec/chalkboard-lib
install -m 0755 "$REPO/scripts/fedora/check-app-menu.sh" \
  /usr/local/libexec/chalkboard-check-app-menu
install -m 0755 "$REPO/scripts/fedora/curate-app-menu.sh" \
  /usr/local/libexec/chalkboard-curate-app-menu

if output=$(/usr/local/libexec/chalkboard-check-app-menu 2>&1); then
  pass "the installed chalkboard-check-app-menu runs from /usr/local/libexec"
else
  fail "the installed chalkboard-check-app-menu cannot run from /usr/local/libexec: $output"
fi

# Same script, invoked from an unrelated working directory and a bare
# environment, which is how a systemd unit or verify.sh would call it.
if (cd / && env -i /usr/local/libexec/chalkboard-check-app-menu >/dev/null 2>&1); then
  pass "the installed helper works with an empty environment and an unrelated cwd"
else
  fail "the installed helper needs a specific environment or working directory"
fi

# And it must still be the same answer as running it from the repository.
if (cd / && env -i "$REPO/scripts/fedora/check-app-menu.sh" >/dev/null 2>&1); then
  pass "running from the repository gives the same verdict"
else
  fail "the repository copy and the installed copy disagree"
fi

rm -f /usr/local/libexec/chalkboard-check-app-menu \
      /usr/local/libexec/chalkboard-curate-app-menu \
      /usr/local/libexec/chalkboard-lib

# ---- 10. the immutable policy cannot be overridden from the child's home ----
# An audit claimed the kiosk policy was defeated because XDG_CONFIG_DIRS is a
# fallback path and KConfig resolves ~/.config/kdeglobals first. Measured here
# with real KConfig on Fedora 43, and the claim does not hold: KConfig treats a
# [$i] group or key as immutable, and a user file cannot override it even when
# the user marks their own group [$i]. Both policy files rely on that marker, so
# this asserts the behaviour rather than re-raising it.
# The [$i] markers in the fixtures below are literal KConfig syntax and must
# not be expanded by the shell.
# shellcheck disable=SC2016
policy_root=$(mktemp -d)
mkdir -p "$policy_root/xdg" "$policy_root/home/.config" "$policy_root/work"
install -m 0644 "$REPO/config/fedora/kde/kdeglobals" "$policy_root/xdg/kdeglobals"
install -m 0644 "$REPO/config/fedora/kde/kglobalshortcutsrc" \
  "$policy_root/xdg/kglobalshortcutsrc"
export XDG_CONFIG_HOME="$policy_root/home/.config"
export XDG_CONFIG_DIRS="$policy_root/xdg:/etc/xdg"
kde_read() {
  kreadconfig6 --file kdeglobals --group 'KDE Action Restrictions' \
    --key run_command 2>/dev/null
}
shortcut_read() {
  kreadconfig6 --file kglobalshortcutsrc --group plasmashell \
    --key 'activate application launcher' 2>/dev/null
}

policy_value=$(kde_read)
if [[ "$policy_value" == false ]]; then
  pass 'the policy restricts run_command with no user file present'
else
  fail "the policy did not take effect: run_command=$policy_value"
fi

# A user file trying to re-enable it, without and then with its own marker.
printf '[KDE Action Restrictions]\nrun_command=true\n' >"$XDG_CONFIG_HOME/kdeglobals"
if [[ "$(kde_read)" == false ]]; then
  pass 'a user kdeglobals cannot re-enable run_command'
else
  fail "a user kdeglobals overrode the policy: run_command=$(kde_read)"
fi
printf '[KDE Action Restrictions][$i]\nrun_command=true\n' >"$XDG_CONFIG_HOME/kdeglobals"
if [[ "$(kde_read)" == false ]]; then
  pass 'a user kdeglobals marked [$i] still cannot re-enable run_command'
else
  fail "a user \$i marker overrode the policy: run_command=$(kde_read)"
fi

# The same question for the shortcut lockdown, which marks keys rather than
# groups.
rm -f "$XDG_CONFIG_HOME/kdeglobals"
printf '[plasmashell]\nactivate application launcher[$i]=Meta,Alt+F2,Activate Application Launcher\n' \
  >"$XDG_CONFIG_HOME/kglobalshortcutsrc"
if [[ "$(shortcut_read)" == none* ]]; then
  pass 'a user kglobalshortcutsrc cannot rebind the application launcher'
else
  fail "a user kglobalshortcutsrc rebound the launcher: $(shortcut_read)"
fi
rm -f "$XDG_CONFIG_HOME/kglobalshortcutsrc"

# Dropping a marker is the one way to lose this, and it is silent. tests/static.sh
# asserts the markers are present; confirm here that a marker really is what makes
# the difference, so the assertion is not cargo cult.
sed 's/\[\$i\]$//' "$REPO/config/fedora/kde/kdeglobals" >"$policy_root/xdg/kdeglobals"
printf '[KDE Action Restrictions]\nrun_command=true\n' >"$XDG_CONFIG_HOME/kdeglobals"
if [[ "$(kde_read)" == true ]]; then
  pass 'without the [$i] marker the user file does win, so the marker is load-bearing'
else
  fail 'the marker is not load-bearing; the static check may be asserting nothing'
fi
install -m 0644 "$REPO/config/fedora/kde/kdeglobals" "$policy_root/xdg/kdeglobals"
rm -rf "$policy_root"
unset XDG_CONFIG_HOME XDG_CONFIG_DIRS

if (( failures > 0 )); then
  printf '\ncontainer integration: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '\nContainer integration tests passed (%s application entries under test).\n' "$installed"
