#!/usr/bin/env bash

set -Eeuo pipefail

choice="$(kdialog --title "Power" --menu "What should the device do?" \
  shutdown "Shut Down" \
  reboot "Restart" \
  cancel "Cancel")" || exit 0

case "$choice" in
  shutdown)
    if kdialog --title "Shut Down" --warningyesno \
        "Shut down this device now?"; then
      systemctl poweroff
    fi
    ;;
  reboot)
    if kdialog --title "Restart" --warningyesno \
        "Restart this device now?"; then
      systemctl reboot
    fi
    ;;
  cancel)
    ;;
esac
