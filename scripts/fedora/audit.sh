#!/usr/bin/env bash

set -Eeuo pipefail

section() {
  printf '\n[%s]\n' "$1"
}

value() {
  printf '%-24s %s\n' "$1" "$2"
}

command_version() {
  local command_name="$1"
  shift

  if command -v "$command_name" >/dev/null 2>&1; then
    value "$command_name" "$("$command_name" "$@" 2>&1 | sed -n '1p')"
  else
    value "$command_name" "not found"
  fi
}

section "Operating system"
if [[ -r /etc/os-release ]]; then
  # Values in os-release are distribution-provided shell assignments.
  source /etc/os-release
  value "name" "${PRETTY_NAME:-unknown}"
  value "id" "${ID:-unknown}"
  value "version_id" "${VERSION_ID:-unknown}"
else
  value "os-release" "not readable"
fi
value "kernel" "$(uname -r)"
value "architecture" "$(uname -m)"

section "Desktop session"
value "desktop" "${XDG_CURRENT_DESKTOP:-not set}"
value "session_type" "${XDG_SESSION_TYPE:-not set}"
value "session_name" "${DESKTOP_SESSION:-not set}"
if command -v rpm >/dev/null 2>&1; then
  for package in plasma-desktop plasma-workspace kwin sddm tuned tuned-ppd power-profiles-daemon; do
    value "$package" "$(rpm -q "$package" 2>/dev/null || printf 'not installed')"
  done
fi

section "System services"
if command -v systemctl >/dev/null 2>&1; then
  for unit in NetworkManager.service systemd-resolved.service sddm.service tuned.service tuned-ppd.service power-profiles-daemon.service; do
    if systemctl cat "$unit" >/dev/null 2>&1; then
      state="$(systemctl is-active "$unit" 2>/dev/null || true)"
      enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
      value "$unit" "active=${state:-unknown}, enabled=${enabled:-unknown}"
    else
      value "$unit" "not installed"
    fi
  done
else
  value "systemctl" "not found"
fi

section "Networking"
command_version nmcli --version
command_version resolvectl --version
if command -v resolvectl >/dev/null 2>&1; then
  dns_servers="$(resolvectl dns 2>/dev/null | sed -E 's/[[:space:]]+/ /g' | paste -sd ';' - || true)"
  value "configured_dns" "${dns_servers:-unavailable}"
fi

section "Input and power capabilities"
command_version libinput --version
command_version powerprofilesctl version
if command -v loginctl >/dev/null 2>&1; then
  value "logind" "available"
else
  value "logind" "not found"
fi

section "Hardware"
for field in product_name product_version sys_vendor; do
  path="/sys/class/dmi/id/$field"
  if [[ -r "$path" ]]; then
    value "$field" "$(<"$path")"
  fi
done

section "Result"
value "changes_made" "none"
value "next_step" "review this output before running mutating setup"
