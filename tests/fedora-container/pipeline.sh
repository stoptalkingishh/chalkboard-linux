#!/usr/bin/env bash
# Full provisioning pipeline against a real Fedora 43 root filesystem, with
# systemd as PID 1.
#
# This is the first automated exercise of deploy.sh, finalize-lockdown.sh,
# verify.sh, and rollback.sh. It found two defects that no other test could:
#
#   1. apply-family-dns.sh set both address families in one nmcli modify.
#      NetworkManager rejects ipv6.dns on a connection whose ipv6.method is
#      disabled and applies a modify atomically, so the rejection discarded the
#      IPv4 filtering too. Because the dispatcher runs on every activation and
#      NetworkManager ignores its exit status, that connection silently kept an
#      unfiltered resolver, and deploy.sh aborted before installing anything else.
#
#   2. check-app-menu.sh sourced "$SCRIPT_DIR/lib.sh", but it is installed as
#      /usr/local/libexec/chalkboard-check-app-menu, where lib.sh is installed
#      under the name chalkboard-lib. The installed copy could not find it, so
#      finalize-lockdown.sh aborted before writing the finalized marker and
#      verify.sh reported two failures on a freshly deployed device.
#
# first-login.sh cannot run: it needs a live Plasma Shell to evaluate panel.js
# against, and there is no display server, no D-Bus, and no Plasma here. Its
# outputs are stood in so the later phases can be exercised.
#
# One verify.sh check is expected to fail in this environment and is not a
# defect: "rotation sensor service is active". iio-sensor-proxy is installed but
# has no IIO device to attach to, because a container has no sensors.
set -u
REPO=/repo
APPSRC=/home/chalkboard/.config/plasma-org.kde.plasma.desktop-appletsrc

step() { printf '\n========== %s ==========\n' "$*"; }
res() { if [[ "$2" == 0 ]]; then printf 'OK    %s\n' "$1"; else printf 'FAIL  %s (exit %s)\n' "$1" "$2"; fi; }

step '1. create-child-user.sh'
bash "$REPO/scripts/fedora/create-child-user.sh" >/tmp/child.log 2>&1
res 'create-child-user.sh' "$?"
tail -4 /tmp/child.log

step '2. deploy.sh'
bash "$REPO/scripts/fedora/deploy.sh" >/tmp/deploy.log 2>&1
deploy_rc=$?
res 'deploy.sh' "$deploy_rc"
grep -oE '^\[chalkboard\] .*' /tmp/deploy.log
[[ $deploy_rc -ne 0 ]] && { echo '--- deploy tail ---'; tail -12 /tmp/deploy.log; }

step '3. deploy.sh re-run (must be idempotent)'
bash "$REPO/scripts/fedora/deploy.sh" >/tmp/deploy2.log 2>&1
res 'deploy.sh re-run' "$?"
[[ -s /tmp/deploy2.log ]] && { echo '--- re-run tail ---'; tail -6 /tmp/deploy2.log; }

step '4. installed packages'
for p in plasma-nm plasma-pa bluedevil plasma-keyboard iio-sensor-proxy kdialog \
         gcompris-qt kcalc kmines ktuberling kolourpaint libreoffice-writer \
         cage vivaldi-stable; do
  printf '  %-22s %s\n' "$p" "$(rpm -q "$p" 2>/dev/null || echo MISSING)"
done
printf '  %-22s %s\n' 'flatpak CuteMaze' \
  "$(flatpak info --system org.gottcode.CuteMaze >/dev/null 2>&1 && echo installed || echo MISSING)"

step '5. managed files installed by deploy.sh'
miss=0
for f in /usr/local/libexec/chalkboard-first-login \
         /usr/local/libexec/chalkboard-power-menu \
         /usr/local/libexec/chalkboard-curate-app-menu \
         /usr/local/libexec/chalkboard-check-app-menu \
         /usr/local/sbin/chalkboard-weather \
         /usr/local/sbin/chalkboard-gcompris-mode \
         /usr/local/share/chalkboard/panel.js \
         /usr/local/share/chalkboard/app-allowlist.txt \
         /usr/local/share/chalkboard/weather.js \
         /etc/xdg/plasma-workspace/env/10-chalkboard-kiosk.sh \
         /etc/sddm.conf.d/90-chalkboard-autologin.conf \
         /etc/systemd/logind.conf.d/90-chalkboard-power.conf \
         /etc/systemd/sleep.conf.d/90-chalkboard-disable-sleep.conf \
         /etc/opt/vivaldi/policies/managed/chalkboard.json \
         /usr/local/share/wayland-sessions/chalkboard-gcompris.desktop; do
  if [[ -e "$f" ]]; then printf '  present  %s\n' "$f"
  else printf '  MISSING  %s\n' "$f"; miss=$((miss+1)); fi
done
printf '  -> %s missing\n' "$miss"
diff -q /usr/local/share/chalkboard/panel.js "$REPO/config/fedora/kde/panel.js" >/dev/null 2>&1 \
  && echo '  panel.js matches the repository' || echo '  FAIL panel.js differs'

step '6. child configuration'
for f in powerdevilrc kscreenlockerrc kwalletrc kwinrc; do
  printf '  %-20s %s\n' "$f" "$([[ -f /home/chalkboard/.config/$f ]] && echo present || echo MISSING)"
done
echo "  kwinrc TabletMode:      $(grep -E '^TabletMode=' /home/chalkboard/.config/kwinrc 2>/dev/null || echo absent)"
echo "  kwinrc InputMethod:     $(grep -E '^InputMethod=' /home/chalkboard/.config/kwinrc 2>/dev/null || echo absent)"
echo "  kwinrc VirtualKeyboard: $(grep -E '^VirtualKeyboardEnabled=' /home/chalkboard/.config/kwinrc 2>/dev/null || echo absent)"
echo "  autostart first-login:  $([[ -f /home/chalkboard/.config/autostart/chalkboard-first-login.desktop ]] && echo present || echo MISSING)"
echo "  child launchers:        $(find /home/chalkboard/.local/share/applications -name 'chalkboard-*.desktop' 2>/dev/null | wc -l)"
echo "  home ownership:         $(stat -c '%U' /home/chalkboard)"

step '7. DNS'
echo "  /etc/chalkboard mode:        $(stat -c '%U:%a' /etc/chalkboard 2>/dev/null)"
echo "  resolver drop-in:            $(find /etc/systemd/resolved.conf.d -maxdepth 1 -type f -printf '%f ' 2>/dev/null)"
sed 's/^/    /' /etc/systemd/resolved.conf.d/60-chalkboard-family.conf 2>/dev/null
echo "  family-dns helper:           $([[ -x /usr/local/sbin/chalkboard-family-dns ]] && echo executable || echo MISSING)"
echo "  NM dispatcher:               $([[ -x /etc/NetworkManager/dispatcher.d/90-chalkboard-family-dns ]] && echo executable || echo MISSING)"
echo "  effective per-connection DNS:"
while IFS=: read -r u t; do
  [[ "$t" =~ ^(802-11-wireless|802-3-ethernet)$ ]] || continue
  printf '    %s (%s) ipv4.dns=%s ipv6.method=%s\n' "$u" "$t" \
    "$(nmcli -g ipv4.dns connection show "$u" 2>/dev/null)" \
    "$(nmcli -g ipv6.method connection show "$u" 2>/dev/null)"
done < <(nmcli -t -f UUID,TYPE connection show)
echo "  resolvectl sees: $(resolvectl dns 2>/dev/null | tr '\n' ' ' | cut -c1-100)"

step '8. sleep targets masked'
for t in sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do
  printf '  %-32s %s\n' "$t" "$(systemctl is-enabled "$t" 2>&1)"
done

step '9. simulate the first-login panel provisioning'
# first-login.sh cannot run: it needs a live Plasma Shell to evaluate panel.js
# against. Stand in the artefacts it would have produced, using the exact layout
# verified in the container, so the remaining phases can be exercised.
install -d -o chalkboard -g chalkboard -m 0700 /home/chalkboard/.local/state/chalkboard
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
favoriteApps=applications:chalkboard-gcompris.desktop,preferred://filemanager
showRecentDocs=false
useExtraRunners=false

[Containments][75][Applets][77]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][75][Applets][77][Configuration][General]
iconSpacing=2
launchers=applications:chalkboard-gcompris.desktop,preferred://filemanager
APPL
chown chalkboard:chalkboard "$APPSRC"
touch /home/chalkboard/.local/state/chalkboard/plasma-provisioned
echo '  provisioning artefacts in place'

step '10. finalize-lockdown.sh'
bash "$REPO/scripts/fedora/finalize-lockdown.sh" >/tmp/finalize.log 2>&1
res 'finalize-lockdown.sh' "$?"
sed 's/^/  /' /tmp/finalize.log
echo "  curated: $(grep -o 'hiddenApplications=' "$APPSRC" | head -1)$(grep -c '^hiddenApplications=' "$APPSRC") key(s)"
echo "  /etc/xdg/chalkboard/kdeglobals: $([[ -f /etc/xdg/chalkboard/kdeglobals ]] && echo present || echo MISSING)"
echo "  /var/lib/chalkboard/finalized:  $([[ -f /var/lib/chalkboard/finalized ]] && echo present || echo MISSING)"

step '11. verify.sh'
bash "$REPO/scripts/fedora/verify.sh" >/tmp/verify.log 2>&1
verify_rc=$?
sed 's/^/  /' /tmp/verify.log
printf '  verify exit: %s\n' "$verify_rc"

step '12. re-running finalize (idempotency)'
bash "$REPO/scripts/fedora/finalize-lockdown.sh" >/tmp/finalize2.log 2>&1
res 'finalize-lockdown.sh re-run' "$?"

step '13. weather is refused after finalization'
bash "$REPO/scripts/fedora/weather.sh" enable --provider noaa --location 'TEST, TS' >/tmp/weather.log 2>&1
res 'weather enable after finalize (must be refused)' "$?"
tail -2 /tmp/weather.log | sed 's/^/  /'

step '14. rollback.sh'
bash "$REPO/scripts/fedora/rollback.sh" >/tmp/rollback.log 2>&1
res 'rollback.sh' "$?"
sed 's/^/  /' /tmp/rollback.log
echo "  sleep.target after rollback: $(systemctl is-enabled sleep.target 2>&1)"
echo "  /etc/xdg/chalkboard/kdeglobals still present: $([[ -f /etc/xdg/chalkboard/kdeglobals ]] && echo yes || echo no)"
echo "  curation still present: $(grep -c '^hiddenApplications=' "$APPSRC" 2>/dev/null) key(s)"
echo "  panel.js still present: $([[ -f /usr/local/share/chalkboard/panel.js ]] && echo yes || echo no)"
