#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
else
  # Installed entry point.
  # shellcheck source=/dev/null
  source /usr/local/libexec/chalkboard-lib
fi

usage() {
  cat <<'EOF'
Usage:
  weather.sh enable --provider noaa --location "STATION NAME, ST"
  weather.sh disable

NOAA receives the selected station/coordinates and the device IP over HTTPS.
The feature uses no API key. Changes take effect at the next child login.
EOF
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

action="$1"
shift
provider=""
location=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || die "--provider requires a value"
      provider="$2"
      shift 2
      ;;
    --location)
      [[ $# -ge 2 ]] || die "--location requires a value"
      location="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$action" in
  enable)
    [[ "$provider" == noaa ]] || die "the supported provider is noaa"
    [[ "$location" =~ ^[^\|[:cntrl:]]+,[[:space:]][A-Z]{2}$ ]] \
      || die 'location must be an exact NOAA station name such as "STATION NAME, ST"'
    ;;
  disable)
    [[ -z "$provider" && -z "$location" ]] \
      || die "disable does not accept provider or location"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *) die "expected enable or disable" ;;
esac

require_root
require_fedora
if [[ -f "$STATE_DIR/finalized" ]]; then
  die "the child desktop is finalized; weather must be configured before finalize-lockdown.sh"
fi
[[ -f "$STATE_DIR/child-user" ]] || die "deploy Chalkboard before configuring weather"
CHILD_USER="$(<"$STATE_DIR/child-user")"
CHILD_HOME="$(child_home "$CHILD_USER")"
ASSET_DIR="/usr/local/share/chalkboard"
CONFIG_FILE="/etc/chalkboard/weather.conf"
AUTOSTART_FILE="$CHILD_HOME/.config/autostart/chalkboard-weather.desktop"
config_tmp="$(mktemp)"
trap 'rm -f "$config_tmp"' EXIT

if [[ "$action" == enable ]]; then
  log "installing Fedora's packaged KDE weather widget"
  dnf -y install kdeplasma-addons
  [[ -f /usr/share/plasma/plasmoids/org.kde.plasma.weather/metadata.json ]] \
    || die "org.kde.plasma.weather was not installed"
  if [[ -r /usr/share/plasma/weather/noaa_station_list.xml ]]; then
    grep -Fq "\"$location\"" /usr/share/plasma/weather/noaa_station_list.xml \
      || die "unknown NOAA station; use a station listed in /usr/share/plasma/weather/noaa_station_list.xml"
  fi

  install -d -o root -g root -m 0755 /etc/chalkboard
  printf '[Weather]\nEnabled=true\nProvider=%s\nLocation=%s\n' \
    "$provider" "$location" >"$config_tmp"
else
  install -d -o root -g root -m 0755 /etc/chalkboard
  printf '[Weather]\nEnabled=false\n' >"$config_tmp"
fi
install -o root -g root -m 0644 "$config_tmp" "$CONFIG_FILE"

# Reconciliation runs as the child so it has the correct Plasma D-Bus session.
install -D -o "$CHILD_USER" -g "$CHILD_USER" -m 0644 \
  "$ASSET_DIR/weather-autostart.desktop" "$AUTOSTART_FILE"
rm -f "$CHILD_HOME/.local/state/chalkboard/weather-enabled"
restorecon -F "$CONFIG_FILE" "$AUTOSTART_FILE" 2>/dev/null || true

log "weather $action requested; reboot or log the child out and back in"
