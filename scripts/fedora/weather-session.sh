#!/usr/bin/env bash

set -Eeuo pipefail

STATE_DIR="$HOME/.local/state/chalkboard"
CONFIG_FILE="/etc/chalkboard/weather.conf"
WEATHER_SCRIPT="/usr/local/share/chalkboard/weather.js"
AUTOSTART_FILE="$HOME/.config/autostart/chalkboard-weather.desktop"

install -d -m 0700 "$STATE_DIR"
exec >>"$STATE_DIR/weather.log" 2>&1

for _ in $(seq 1 120); do
  if [[ -f "$STATE_DIR/plasma-provisioned" ]] \
      && qdbus-qt6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

[[ -f "$STATE_DIR/plasma-provisioned" ]] || {
  printf '[chalkboard] baseline panel is not provisioned; weather deferred\n'
  exit 1
}

# The immutable kiosk policy can block D-Bus panel scripting (after
# finalize-lockdown or when the shell is still unlocking). Log the refusal and
# exit cleanly instead of failing the autostart; the widget already placed
# before finalization keeps working and the command refuses changes post-lock.
reconcile_output="$(qdbus-qt6 org.kde.plasmashell /PlasmaShell \
  org.kde.PlasmaShell.evaluateScript "$(<"$WEATHER_SCRIPT")" 2>&1)" || {
  printf '[chalkboard] weather reconcile unavailable (%s); retrying at next login\n' \
    "$reconcile_output"
  exit 0
}

if grep -Fqx 'Enabled=true' "$CONFIG_FILE"; then
  touch "$STATE_DIR/weather-enabled"
  printf '[chalkboard] optional weather enabled\n'
else
  rm -f "$STATE_DIR/weather-enabled" "$AUTOSTART_FILE"
  printf '[chalkboard] optional weather disabled\n'
fi
