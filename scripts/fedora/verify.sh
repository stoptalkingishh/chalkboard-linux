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

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
valid_nextdns_profile() {
  [[ "$1" =~ ^[0-9a-f]{6}$ ]]
}

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
nextdns_profile_is_root_only() {
  [[ "$(stat -c '%u:%a' /etc/chalkboard/nextdns-profile)" == 0:600 ]]
}

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
nextdns_is_configured() {
  local id="$1" uuid
  uuid="$(active_connection_uuid)" || return 1
  [[ -n "$uuid" ]] || return 1
  # Check the effective per-link data from NetworkManager, which preserves the
  # DoT server-name tokens that systemd-resolved may render differently.
  nmcli -g ipv4.dns,ipv6.dns connection show "$uuid" |
    grep -Fq "45.90.28.0#$id.dns.nextdns.io"
}

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
active_connection_device() {
  nmcli -t -f DEVICE,TYPE connection show --active |
    awk -F: '$2 ~ /^(802-11-wireless|802-3-ethernet)$/ { print $1; exit }'
}

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
active_connection_uuid() {
  nmcli -t -f UUID,TYPE connection show --active |
    awk -F: '$2 ~ /^(802-11-wireless|802-3-ethernet)$/ { print $1; exit }'
}

# Invoked indirectly by check. Asserts the effective resolved setting on the
# active link rather than only the drop-in file, so a higher-priority
# overridden drop-in is caught.
# shellcheck disable=SC2317,SC2329
strict_dot_effective() {
  local device
  device="$(active_connection_device)" || return 1
  [[ -n "$device" ]] || return 1
  resolvectl status "$device" 2>/dev/null |
    grep -Eq 'DNS Over TLS: yes|DNS-over-TLS: yes'
}

# Invoked indirectly by check.
# shellcheck disable=SC2317,SC2329
cloudflare_is_configured() {
  resolvectl dns | grep -q '1.1.1.3'
}

# Invoked indirectly by check. Confirms the Cloudflare drop-in is present and
# intentionally opportunistic with an encrypted fallback, so a stale NextDNS
# drop-in or missing file is detected.
# shellcheck disable=SC2317,SC2329
cloudflare_dropin_effective() {
  grep -Fxq 'DNSOverTLS=opportunistic' /etc/systemd/resolved.conf.d/60-chalkboard-family.conf &&
    grep -Eq '^FallbackDNS=' /etc/systemd/resolved.conf.d/60-chalkboard-family.conf
}

check "child account exists" getent passwd chalkboard
check "child account is not an administrator" bash -c \
  "! id -nG chalkboard | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'"
check "Vivaldi is installed" rpm -q vivaldi-stable
check "Plasma network controls are installed" rpm -q plasma-nm
check "Plasma audio controls are installed" rpm -q plasma-pa
check "Plasma Bluetooth controls are installed" rpm -q bluedevil
check "Plasma virtual keyboard is installed" rpm -q plasma-keyboard
check "rotation sensor service is installed" rpm -q iio-sensor-proxy
check "rotation sensor service is active" systemctl is-active iio-sensor-proxy
check "automatic tablet mode is configured" grep -Fqx 'TabletMode=auto' \
  /home/chalkboard/.config/kwinrc
check "Plasma Keyboard is configured" grep -Fqx \
  'InputMethod=/usr/share/applications/org.kde.plasma.keyboard.desktop' \
  /home/chalkboard/.config/kwinrc
check "virtual keyboard is enabled" grep -Fqx 'VirtualKeyboardEnabled=true' \
  /home/chalkboard/.config/kwinrc
check "confirmed power menu is installed" test -x \
  /usr/local/libexec/chalkboard-power-menu
check "Cage kiosk compositor is installed" rpm -q cage
check "optional GCompris mode command is installed" test -x \
  /usr/local/sbin/chalkboard-gcompris-mode
check "GCompris Wayland session is installed" test -f \
  /usr/local/share/wayland-sessions/chalkboard-gcompris.desktop
for package in gcompris-qt kolourpaint kcalc libreoffice-writer ktuberling kmines; do
  check "$package is installed" rpm -q "$package"
done
check "CuteMaze is installed" flatpak info --system org.gottcode.CuteMaze
check "systemd-resolved is active" systemctl is-active systemd-resolved
if [[ -e /etc/chalkboard/nextdns-profile ]]; then
  if [[ -r /etc/chalkboard/nextdns-profile ]]; then
    nextdns_profile="$(</etc/chalkboard/nextdns-profile)"
  else
    nextdns_profile=""
  fi
  check "NextDNS profile is valid" valid_nextdns_profile "$nextdns_profile"
  check "NextDNS profile is root-only" nextdns_profile_is_root_only
  check "NextDNS is configured" nextdns_is_configured "$nextdns_profile"
  check "NextDNS uses strict DNS-over-TLS" strict_dot_effective
else
  check "Cloudflare Family DNS is configured" cloudflare_is_configured
  check "Cloudflare drop-in is in effect" cloudflare_dropin_effective
fi
if systemctl is-enabled suspend.target 2>/dev/null | grep -qx masked; then
  printf 'PASS  suspend target is masked\n'
else
  printf 'FAIL  suspend target is not masked\n'
  failures=$((failures + 1))
fi
check "SDDM autologin is configured" grep -Fq 'User=chalkboard' \
  /etc/sddm.conf.d/90-chalkboard-autologin.conf
if [[ -f /var/lib/chalkboard/gcompris-mode-enabled ]]; then
  check "GCompris mode selects its SDDM session" cmp -s \
    /usr/local/share/chalkboard/gcompris-sddm.conf \
    /etc/sddm.conf.d/95-chalkboard-gcompris.conf
else
  check "GCompris mode is disabled cleanly" test ! -e \
    /etc/sddm.conf.d/95-chalkboard-gcompris.conf
fi
check "Plasma panel was provisioned" test -f \
  /home/chalkboard/.local/state/chalkboard/plasma-provisioned
check "Application Dashboard was provisioned" grep -Fq \
  'plugin=org.kde.plasma.kickerdash' \
  /home/chalkboard/.config/plasma-org.kde.plasma.desktop-appletsrc
check "Icons-only Task Manager was provisioned" grep -Fq \
  'plugin=org.kde.plasma.icontasks' \
  /home/chalkboard/.config/plasma-org.kde.plasma.desktop-appletsrc
check "immutable KDE policy is finalized" test -f /var/lib/chalkboard/finalized
if [[ -x /usr/local/libexec/chalkboard-screen-time ]]; then
  check "screen-time configuration is valid" /usr/local/libexec/chalkboard-screen-time check
  check "screen-time config is root-owned and private" bash -c \
    "[[ \$(stat -c '%u %a' /etc/chalkboard/screen-time.conf) == '0 600' ]]"
fi

printf '\nFailures: %s\n' "$failures"
exit "$failures"
