#!/usr/bin/env bash

set -Eeuo pipefail

STATE_DIR="$HOME/.local/state/chalkboard"
LOG_FILE="$STATE_DIR/first-login.log"
PANEL_SCRIPT="/usr/local/share/chalkboard/panel.js"

install -d -m 0700 "$STATE_DIR"
exec >>"$LOG_FILE" 2>&1

printf '[chalkboard] starting first-login provisioning\n'

for _ in $(seq 1 60); do
  if qdbus-qt6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

qdbus-qt6 org.kde.plasmashell /PlasmaShell \
  org.kde.PlasmaShell.evaluateScript "$(<"$PANEL_SCRIPT")"

# The internal 2736x1824 display is high density. KScreen applies this through
# its supported output API and retains it across laptop and tablet modes.
if kscreen-doctor -o 2>/dev/null | grep -q 'eDP-1'; then
  kscreen-doctor output.eDP-1.scale.1.75 || \
    printf '[chalkboard] unable to apply preferred internal-display scale\n'
fi

# KWin exposes touchpad settings through its user-session D-Bus API. A
# detachable without a connected touchpad legitimately returns no devices.
while IFS= read -r device; do
  [[ -n "$device" ]] || continue
  if busctl --user get-property org.kde.KWin \
      "/org/kde/KWin/InputDevice/$device" \
      org.kde.KWin.InputDevice touchpad 2>/dev/null | grep -q 'true'; then
    busctl --user set-property org.kde.KWin \
      "/org/kde/KWin/InputDevice/$device" \
      org.kde.KWin.InputDevice tapToClick b false
  fi
done < <(qdbus-qt6 org.kde.KWin /org/kde/KWin/InputDevice \
  org.kde.KWin.InputDeviceManager.ListPointers 2>/dev/null || true)

touch "$STATE_DIR/plasma-provisioned"
rm -f "$HOME/.config/autostart/chalkboard-first-login.desktop"
printf '[chalkboard] first-login provisioning complete\n'
