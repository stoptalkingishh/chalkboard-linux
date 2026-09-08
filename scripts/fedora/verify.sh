#!/usr/bin/env bash

set -Eeuo pipefail

failures=0

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$description"
  else
    printf 'FAIL  %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check "child account exists" getent passwd chalkboard
check "child account is not an administrator" bash -c \
  "! id -nG chalkboard | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'"
check "Vivaldi is installed" rpm -q vivaldi-stable
check "Plasma network controls are installed" rpm -q plasma-nm
check "Plasma audio controls are installed" rpm -q plasma-pa
check "Plasma Bluetooth controls are installed" rpm -q bluedevil
check "confirmed power menu is installed" test -x \
  /usr/local/libexec/chalkboard-power-menu
for package in gcompris-qt kolourpaint kcalc libreoffice-writer ktuberling kmines; do
  check "$package is installed" rpm -q "$package"
done
check "CuteMaze is installed" flatpak info --system org.gottcode.CuteMaze
check "systemd-resolved is active" systemctl is-active systemd-resolved
check "Family DNS is configured" bash -c \
  "resolvectl dns | grep -q '1.1.1.3'"
if systemctl is-enabled suspend.target 2>/dev/null | grep -qx masked; then
  printf 'PASS  suspend target is masked\n'
else
  printf 'FAIL  suspend target is not masked\n'
  failures=$((failures + 1))
fi
check "SDDM autologin is configured" grep -Fq 'User=chalkboard' \
  /etc/sddm.conf.d/90-chalkboard-autologin.conf
check "Plasma panel was provisioned" test -f \
  /home/chalkboard/.local/state/chalkboard/plasma-provisioned
check "immutable KDE policy is finalized" test -f /var/lib/chalkboard/finalized
if [[ -x /usr/local/libexec/chalkboard-screen-time ]]; then
  check "screen-time configuration is valid" /usr/local/libexec/chalkboard-screen-time check
  check "screen-time config is root-owned and private" bash -c \
    "[[ \$(stat -c '%u %a' /etc/chalkboard/screen-time.conf) == '0 600' ]]"
fi

printf '\nFailures: %s\n' "$failures"
exit "$failures"
