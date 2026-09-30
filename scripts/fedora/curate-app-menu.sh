#!/usr/bin/env bash

# Curates the child Application Dashboard (kickerdash) to an explicit
# allowlist. Every installed application that is not allowlisted is hidden
# from the child's app menu. Idempotent and root-only.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Visibility, allowlist parsing, and the kickerdash applet lookup live in lib.sh
# so this script and check-app-menu.sh cannot disagree about what the child can
# see. They did disagree once, and the verifier was wrong.
#
# Installed as /usr/local/libexec/chalkboard-curate-app-menu, where lib.sh is
# installed under its installed name. Same two-location pattern weather.sh uses.
if [[ -r "$SCRIPT_DIR/lib.sh" ]]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
else
  # shellcheck source=lib.sh
  source /usr/local/libexec/chalkboard-lib
fi
if [[ -f "$SCRIPT_DIR/../../config/fedora/app-allowlist.txt" ]]; then
  ALLOWLIST_FILE="${CHALKBOARD_ALLOWLIST:-$SCRIPT_DIR/../../config/fedora/app-allowlist.txt}"
else
  # Installed entry point.
  ALLOWLIST_FILE="${CHALKBOARD_ALLOWLIST:-/usr/local/share/chalkboard/app-allowlist.txt}"
fi
# The first positional argument wins, so a caller that knows the real account name
# cannot be silently ignored in favour of the default.
CHILD_USER="${1:-${CHALKBOARD_CHILD_USER:-chalkboard}}"
[[ "$CHILD_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
  echo "invalid child user name: $CHILD_USER" >&2
  exit 1
}
CHILD_HOME="$(getent passwd "$CHILD_USER" | cut -d: -f6)"
APPSRC="$CHILD_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -s "$ALLOWLIST_FILE" ]] || { echo "allowlist missing: $ALLOWLIST_FILE" >&2; exit 1; }
getent passwd "$CHILD_USER" >/dev/null || { echo "unknown child user: $CHILD_USER" >&2; exit 1; }
[[ -s "$APPSRC" ]] || { echo "applet config missing: $APPSRC" >&2; exit 1; }

mapfile -t allowed < <(read_allowlist "$ALLOWLIST_FILE")

# Visibility is defined once, in lib.sh, and shared with check-app-menu.sh. Two
# independent enumerations drifted apart in practice.
mapfile -t visible < <(child_visible_applications "$CHILD_HOME")

# hidden = visible - allowlist (preserving directory-first order).
hidden=()
for id in "${visible[@]}"; do
  skip=0
  for allowed_id in "${allowed[@]}"; do
    if [[ "$id" == "$allowed_id" ]]; then skip=1; break; fi
  done
  [[ $skip -eq 0 ]] && hidden+=("$id")
done

# Locate the kickerdash applet within its containment. read returns non-zero at
# EOF with no input, which under `set -e` would abort before the diagnostic on the
# next line could explain why.
containment=''
applet=''
read -r containment applet < <(find_kickerdash_ids "$APPSRC") || true
[[ -n "${containment:-}" && -n "${applet:-}" ]] || {
  echo "kickerdash applet not found" >&2
  exit 1
}

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