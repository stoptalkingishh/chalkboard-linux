#!/usr/bin/env bash
# Deploy the Chalkboard setup inside the container and leave it deployed, so the
# result can be committed into an image with `docker commit`.
#
# This is the deployment half of pipeline.sh, without the rollback step.
#
# first-login.sh cannot run here: it evaluates panel.js through a live Plasma
# Shell, and a container has no display server, no D-Bus, and no Plasma. Its two
# outputs -- the applet config and the plasma-provisioned marker -- are stood in
# so finalize-lockdown.sh and verify.sh can be exercised. Everything else is the
# shipped script, unmodified.
#
# Expected result: verify.sh reports 35 passes and one failure,
# "rotation sensor service is active", because iio-sensor-proxy has no IIO device
# to attach to in a container. Any other failure is a real one.
set -u
REPO=/repo
APPSRC=/home/chalkboard/.config/plasma-org.kde.plasma.desktop-appletsrc

step() { printf '\n-- %s\n' "$*"; }
die() { printf 'DEPLOY FAILED: %s\n' "$*" >&2; exit 1; }

step 'waiting for systemd'
for _ in $(seq 1 40); do
  systemctl is-system-running >/dev/null 2>&1 && break
  sleep 1
done
printf 'systemd: %s\n' "$(systemctl is-system-running 2>&1)"

step 'create-child-user.sh'
bash "$REPO/scripts/fedora/create-child-user.sh" || die 'create-child-user.sh'

step 'deploy.sh'
bash "$REPO/scripts/fedora/deploy.sh" || die 'deploy.sh'
[[ -f /var/lib/chalkboard/deployed ]] || die 'deploy.sh did not record the deployed marker'

step 'stand in for first-login.sh (needs a live Plasma Shell)'
install -d -o chalkboard -g chalkboard -m 0700 \
  /home/chalkboard/.local/state/chalkboard
cat >"$APPSRC" <<'APPL'
[Containments][1]
formfactor=2
immutability=1
location=content
plugin=org.kde.folder

[Containments][75]
formfactor=2
immutability=1
location=bottom
plugin=org.kde.panel

[Containments][75][Applets][76]
immutability=1
plugin=org.kde.plasma.kickerdash

[Containments][75][Applets][76][Configuration][General]
favoriteApps=applications:chalkboard-browser.desktop,applications:chalkboard-coolmath-games.desktop,applications:chalkboard-cutemaze.desktop,applications:chalkboard-gcompris.desktop,applications:chalkboard-kcalc.desktop,applications:chalkboard-kidpix.desktop,applications:chalkboard-kmines.desktop,applications:chalkboard-kolourpaint.desktop,applications:chalkboard-ktuberling.desktop,applications:chalkboard-writer.desktop,applications:chalkboard-teach-your-monster.desktop,preferred://filemanager
showRecentDocs=false
useExtraRunners=false

[Containments][75][Applets][77]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][75][Applets][77][Configuration][General]
iconSpacing=2
launchers=applications:chalkboard-gcompris.desktop,applications:chalkboard-kidpix.desktop,applications:chalkboard-writer.desktop,applications:chalkboard-teach-your-monster.desktop,applications:chalkboard-coolmath-games.desktop,preferred://filemanager
showOnlyCurrentActivity=true
showOnlyCurrentDesktop=true

[Containments][75][General]
AppletOrder=76;77
APPL
chown chalkboard:chalkboard "$APPSRC"
chmod 0600 "$APPSRC"
touch /home/chalkboard/.local/state/chalkboard/plasma-provisioned
echo 'provisioning artefacts in place'

step 'finalize-lockdown.sh'
bash "$REPO/scripts/fedora/finalize-lockdown.sh" || die 'finalize-lockdown.sh'
[[ -f /var/lib/chalkboard/finalized ]] || die 'finalized marker was not written'

step 'verify.sh'
bash "$REPO/scripts/fedora/verify.sh" >/tmp/verify.out 2>&1
verify_rc=$?
sed 's/^/  /' /tmp/verify.out
printf '\n== verify.sh exit: %s\n' "$verify_rc"

# Exactly one failure is expected: iio-sensor-proxy has no IIO device to attach
# to in a container. Anything else is a real failure and must not be ignored.
if grep '^FAIL' /tmp/verify.out | grep -qv 'rotation sensor service is active'; then
  grep '^FAIL' /tmp/verify.out | sed 's/^/  UNEXPECTED: /'
  die 'verify.sh reported a failure other than the sensor service'
fi
if grep -q 'rotation sensor service is active' /tmp/verify.out; then
  echo '  expected in a container: rotation sensor service is active (no IIO device)'
fi
printf '  passes: %s\n' "$(grep -c '^PASS' /tmp/verify.out)"

step 'deployed state'
printf '  child account:        %s\n' "$(id -u chalkboard 2>&1)"
printf '  sleep targets:        %s\n' \
  "$(systemctl is-enabled sleep.target 2>&1)"
printf '  immutable policy:     %s\n' \
  "$([[ -f /etc/xdg/chalkboard/kdeglobals ]] && echo installed || echo MISSING)"
printf '  kiosk config dir:     %s\n' "$(head -1 /etc/xdg/plasma-workspace/env/10-chalkboard-kiosk.sh 2>/dev/null)"
printf '  curated menu:         %s\n' \
  "$(/usr/local/libexec/chalkboard-check-app-menu 2>&1)"
printf '  DNS:                  %s\n' \
  "$(resolvectl dns 2>/dev/null | grep -o '1\.1\.1\.3[^ ]*' | head -1)"
printf '  autologin:            %s\n' \
  "$(grep -h '^User=' /etc/sddm.conf.d/90-chalkboard-autologin.conf 2>/dev/null)"

printf '\nDEPLOY OK\n'
