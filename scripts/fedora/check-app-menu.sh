#!/usr/bin/env bash
# Confirms the child's Plasma applet config really is curated to the allowlist.
#
# Curation writes a static denylist (hiddenApplications) of every application the
# child can see that is NOT in the allowlist. A count threshold cannot express
# that: a list hiding exactly the allowlisted apps passed, a list hiding the two
# genuinely dangerous apps failed, and a missing applet config passed because awk
# exited 2 and the leading negation inverted it. It also failed open whenever the
# threshold drifted, since the real count of installed .desktop files changes on
# every package update.
#
# Both the expected set and the applet lookup come from lib.sh, which
# curate-app-menu.sh also uses, so the verifier cannot drift from the curation it
# is checking.
#
# Read-only. Prints the difference and exits non-zero on any mismatch.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CHILD_USER="${CHALKBOARD_CHILD_USER:-chalkboard}"
APPLETSRC="${CHALKBOARD_APPLETSRC:-}"
ALLOWLIST="${CHALKBOARD_ALLOWLIST:-/usr/local/share/chalkboard/app-allowlist.txt}"
CHILD_HOME="${CHALKBOARD_CHILD_HOME:-$(child_home "$CHILD_USER")}"

[[ -n "$CHILD_HOME" ]] || { printf 'unknown child user: %s\n' "$CHILD_USER" >&2; exit 1; }
[[ -n "$APPLETSRC" ]] || APPLETSRC="$CHILD_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
[[ -f "$APPLETSRC" ]] || { printf 'applet config missing: %s\n' "$APPLETSRC" >&2; exit 1; }
[[ -r "$ALLOWLIST" ]] || { printf 'allowlist missing: %s\n' "$ALLOWLIST" >&2; exit 1; }

# read returns non-zero at EOF with no input, which under `set -e` would abort
# before the explicit "no hiddenApplications key" check below can report it.
hidden=''
hidden="$(read_kickerdash_hidden "$APPLETSRC")" || true
[[ -n "$hidden" ]] || {
  printf 'kickerdash applet has no hiddenApplications key in %s\n' "$APPLETSRC" >&2
  exit 1
}

allowlist_entries="$(read_allowlist "$ALLOWLIST")" || true
[[ -n "$allowlist_entries" ]] || { printf 'allowlist has no entries: %s\n' "$ALLOWLIST" >&2; exit 1; }

expected=$(
  child_visible_applications "$CHILD_HOME" |
    while IFS= read -r entry; do
      grep -qxF "$entry" <<<"$allowlist_entries" || printf '%s\n' "$entry"
    done | sort -u
)
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
