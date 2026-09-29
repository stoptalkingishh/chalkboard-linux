#!/usr/bin/env bash
# Confirms the child's Plasma applet config really is curated to the allowlist.
#
# Curation writes a static denylist (hiddenApplications) of every application the
# child can see that is NOT in the allowlist. A count threshold cannot express
# that: a list hiding the wrong eleven apps, or an allowlisted app, is just as
# wrong as a short list, and a missing applet config is worse than either. So
# recompute the expected denylist from the same inputs curate-app-menu.sh uses
# and compare exactly.
#
# Read-only. Prints the difference and exits non-zero on any mismatch.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CHILD_USER="${CHALKBOARD_CHILD_USER:-chalkboard}"
APPLETSRC="${CHALKBOARD_APPLETSRC:-}"
ALLOWLIST="${CHALKBOARD_ALLOWLIST:-/usr/local/share/chalkboard/app-allowlist.txt}"

# CHALKBOARD_SCAN_DIRS exists so tests can point the scan at a fixture tree. It is
# a space-separated list; unset means the real device paths below.
if [[ -n "${CHALKBOARD_SCAN_DIRS:-}" ]]; then
  read -r -a XDG_DIRS <<<"$CHALKBOARD_SCAN_DIRS"
else
  XDG_DIRS=(
    /usr/share/applications
    /usr/local/share/applications
    /var/lib/flatpak/exports/share/applications
  )
fi

if [[ -z "$APPLETSRC" ]]; then
  APPLETSRC="$(child_home "$CHILD_USER")/.config/plasma-org.kde.plasma.desktop-appletsrc"
fi

[[ -f "$APPLETSRC" ]] || { printf 'applet config missing: %s\n' "$APPLETSRC" >&2; exit 1; }
[[ -r "$ALLOWLIST" ]] || { printf 'allowlist missing: %s\n' "$ALLOWLIST" >&2; exit 1; }

# Locate the kickerdash applet and read its hiddenApplications value, the same
# way curate-app-menu.sh does, so both sides agree on which applet matters.
# read returns non-zero at EOF with no input, which under `set -e` would abort
# before the explicit "no hiddenApplications key" check below can report it.
read -r hidden < <(awk -F= '
  /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]\[Configuration\]\[General\]$/ {
    plugin = ""
    next
  }
  /^plugin=org.kde.plasma.kickerdash$/ { plugin = $0 }
    plugin != "" && /^hiddenApplications=/ { sub(/^hiddenApplications=/, ""); print; exit }
' "$APPLETSRC") || true

[[ -n "$hidden" ]] || {
  printf 'kickerdash applet has no hiddenApplications key in %s\n' "$APPLETSRC" >&2
  exit 1
}

# Strip CR so a repository checkout with CRLF endings does not make every
# allowlist comparison fail on a trailing carriage return.
allowlist_entries=$(tr -d '\r' <"$ALLOWLIST" | grep -E '^[^#[:space:]]' | sort -u)
[[ -n "$allowlist_entries" ]] || { printf 'allowlist has no entries: %s\n' "$ALLOWLIST" >&2; exit 1; }

scan_dirs=()
for dir in "${XDG_DIRS[@]}"; do
  [[ -d "$dir" ]] && scan_dirs+=("$dir")
done
if [[ -z "${CHALKBOARD_SCAN_DIRS:-}" ]]; then
  child_local="$(child_home "$CHILD_USER")/.local/share/applications"
  [[ -d "$child_local" ]] && scan_dirs+=("$child_local")
fi

expected=$(find "${scan_dirs[@]}" -maxdepth 1 -type f -name '*.desktop' -printf '%f\n' 2>/dev/null |
  while IFS= read -r entry; do
    grep -qxF "$entry" <<<"$allowlist_entries" || printf '%s\n' "$entry"
  done | sort -u)

actual=$(printf '%s\n' "$hidden" | tr ',' '\n' | sort -u)
difference=$(comm -3 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected"))

if [[ -n "$difference" ]]; then
  printf 'curation does not match the allowlist.\n' >&2
  printf '  < present in hiddenApplications but should not be:\n' >&2
  comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") | sed 's/^/    /' >&2
  printf '  > installed and visible to the child but not hidden:\n' >&2
  comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") | sed 's/^/    /' >&2
  exit 1
fi

printf 'app menu is curated: %s hidden, %s allowlisted\n' \
  "$(printf '%s\n' "$actual" | grep -c .)" \
  "$(printf '%s\n' "$allowlist_entries" | grep -c .)"
