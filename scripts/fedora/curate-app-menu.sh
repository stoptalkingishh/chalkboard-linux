#!/usr/bin/env bash

# Curates the child Application Dashboard (kickerdash) to an explicit
# allowlist. Every installed application that is not allowlisted is hidden
# from the child's app menu. Idempotent and root-only.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../../config/fedora/app-allowlist.txt" ]]; then
  ALLOWLIST_FILE="${CHALKBOARD_ALLOWLIST:-$SCRIPT_DIR/../../config/fedora/app-allowlist.txt}"
else
  # Installed entry point.
  ALLOWLIST_FILE="${CHALKBOARD_ALLOWLIST:-/usr/local/share/chalkboard/app-allowlist.txt}"
fi
CHILD_USER="${CHALKBOARD_CHILD_USER:-chalkboard}"
CHILD_HOME="$(getent passwd "$CHILD_USER" | cut -d: -f6)"
APPSRC="$CHILD_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
KICKERDASH_PLUGIN=org.kde.plasma.kickerdash

XDG_DIRS=(
  /usr/share/applications
  /usr/local/share/applications
  /var/lib/flatpak/exports/share/applications
  "$CHILD_HOME/.local/share/applications"
)

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -s "$ALLOWLIST_FILE" ]] || { echo "allowlist missing: $ALLOWLIST_FILE" >&2; exit 1; }
getent passwd "$CHILD_USER" >/dev/null || { echo "unknown child user: $CHILD_USER" >&2; exit 1; }
[[ -s "$APPSRC" ]] || { echo "applet config missing: $APPSRC" >&2; exit 1; }

mapfile -t allowed < <(grep -E '^[^#[:space:]]' "$ALLOWLIST_FILE")

# Enumerate every menu entry visible in the child's XDG application dirs.
visible=()
while IFS= read -r -d '' entry; do
  base="$(basename "$entry")"
  [[ "$base" == *.desktop ]] || continue
  grep -q '^Type=Application' "$entry" 2>/dev/null || continue
  if grep -qE '^(NoDisplay|Hidden)=true' "$entry" 2>/dev/null; then
    continue
  fi
  visible+=("$base")
done < <(find "${XDG_DIRS[@]}" -maxdepth 1 -type f -name '*.desktop' -print0 | sort -zu)

# hidden = visible - allowlist (preserving directory-first order).
hidden=()
for id in "${visible[@]}"; do
  skip=0
  for allowed_id in "${allowed[@]}"; do
    if [[ "$id" == "$allowed_id" ]]; then skip=1; break; fi
  done
  [[ $skip -eq 0 ]] && hidden+=("$id")
done

# Locate the kickerdash applet within its containment.
read -r containment applet < <(awk -v plugin="$KICKERDASH_PLUGIN" '
  /^\[Containments\]\[[0-9]+\]$/ { match($0, /\[Containments\]\[([0-9]+)\]$/, m); c=m[1]; next }
  /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
    match($0, /\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$/, m)
    a=m[2]
  }
  $0 == "plugin=" plugin { print c, a; exit }
' "$APPSRC")
[[ -n "${containment:-}" && -n "${applet:-}" ]] || { echo "kickerdash applet not found" >&2; exit 1; }

# Write a StringList of header names. KConfig group paths are written one
# bracket level per --group argument.
hidden_value="$(IFS=,; printf '%s' "${hidden[*]}")"
kwriteconfig6 --file "$APPSRC" \
  --group Containments --group "$containment" \
  --group Applets --group "$applet" \
  --group Configuration --group General \
  --key hiddenApplications "$hidden_value"

chown "$CHILD_USER:$CHILD_USER" "$APPSRC"
echo "curated child app menu: $((${#visible[@]} - ${#hidden[@]})) allowed, ${#hidden[@]} hidden"