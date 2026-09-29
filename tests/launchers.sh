#!/usr/bin/env bash

# Four hand-maintained lists describe the same child app set -- panel.js
# dashboardFavorites, panel.js panelLaunchers, config/fedora/app-allowlist.txt
# and config/fedora/launchers/*.desktop -- and nothing checked that they still
# agree. A launcher added to one list and forgotten in the others surfaces on
# the child device as a missing menu entry, which is exactly the failure this
# suite exists to catch.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PANEL_JS='config/fedora/kde/panel.js'
ALLOWLIST='config/fedora/app-allowlist.txt'
LAUNCHER_DIR='config/fedora/launchers'

# Plasma's preferred-apps URI for the system file manager. It has no
# applications: form because the desktop file comes from the distribution, so
# the check that every allowlisted app appears in dashboardFavorites cannot
# cover it. Asserted separately below.
readonly PREFERRED_FILE_MANAGER='preferred://filemanager'

# System applications the child may launch that are deliberately NOT shipped in
# config/fedora/launchers/: they come from the distribution and are filtered in
# place by scripts/fedora/curate-app-menu.sh. Enumerated one by one on purpose --
# a wildcard here would silently re-admit every desktop file on the system.
readonly SYSTEM_APP_ALLOWLIST=(
  # KDE's file manager. panel.js references it as preferred://filemanager, which
  # resolves through Plasma's own preferred-apps mapping, so there is no
  # chalkboard- copy to curate.
  'org.kde.dolphin.desktop'
)

# Launchers that ship in config/fedora/launchers/ but are intentionally kept out
# of the Dashboard menu and out of the allowlist.
readonly MENU_EXCLUSIONS=(
  # Power control. It is reached from the dedicated panel power icon (the
  # powerLauncher widget in panel.js), not from the Dashboard, so listing it in
  # the menu would give the child a second, unguarded route to it.
  'chalkboard-power.desktop'
)

die() {
  printf '[launchers] %s\n' "$*" >&2
  exit 1
}

list_contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Pull the string literals out of a `const <name> = [ ... ];` block. Requiring
# the block to be present is what makes "panel.js still parses" observable here
# without a JavaScript runtime.
read_js_array() {
  local name="$1"
  sed -n "/^const ${name} = \\[$/,/^\\];$/p" "$PANEL_JS" |
    grep -o '"[^"]*"' |
    tr -d '"'
}

for required in "$PANEL_JS" "$ALLOWLIST" "$LAUNCHER_DIR"; do
  [[ -e "$required" ]] || die "expected $required to exist"
done

dashboard_favorites=()
panel_launchers=()
mapfile -t dashboard_favorites < <(read_js_array dashboardFavorites)
mapfile -t panel_launchers < <(read_js_array panelLaunchers)

# An empty array means panel.js no longer parses, or the constant was renamed or
# reformatted. Either way there is nothing left to cross-check.
[[ ${#dashboard_favorites[@]} -gt 0 ]] ||
  die "panel.js: dashboardFavorites is missing or empty; panel.js no longer parses as expected"
[[ ${#panel_launchers[@]} -gt 0 ]] ||
  die "panel.js: panelLaunchers is missing or empty; panel.js no longer parses as expected"

# (a) every applications:*.desktop referenced from panel.js must be shipped.
for entry in "${dashboard_favorites[@]}" "${panel_launchers[@]}"; do
  case "$entry" in
    applications:*) ;;
    *) continue ;;
  esac
  desktop_name="${entry#applications:}"
  [[ -f "$LAUNCHER_DIR/$desktop_name" ]] ||
    die "panel.js references $entry but $LAUNCHER_DIR/$desktop_name does not exist"
done

allowlist=()
while IFS= read -r line || [[ -n "$line" ]]; do
  entry="${line%%#*}"
  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"
  [[ -n "$entry" ]] || continue
  allowlist+=("$entry")
done <"$ALLOWLIST"

[[ ${#allowlist[@]} -gt 0 ]] || die "$ALLOWLIST is empty"

# (b) every allowlist entry must resolve to a shipped launcher, or be one of the
# named system applications above.
for entry in "${allowlist[@]}"; do
  if list_contains "$entry" "${SYSTEM_APP_ALLOWLIST[@]}"; then
    continue
  fi
  case "$entry" in
    chalkboard-*.desktop) ;;
    *)
      die "allowlist entry $entry is neither a chalkboard-* launcher nor a documented system-app exception"
      ;;
  esac
  [[ -f "$LAUNCHER_DIR/$entry" ]] ||
    die "allowlist entry $entry has no launcher in $LAUNCHER_DIR"
done

# (c) every shipped launcher must be reachable from the app menu, i.e. listed in
# the allowlist, or be one of the named exclusions.
for launcher in "$LAUNCHER_DIR"/*.desktop; do
  desktop_name="$(basename -- "$launcher")"
  if list_contains "$desktop_name" "${MENU_EXCLUSIONS[@]}"; then
    continue
  fi
  list_contains "$desktop_name" "${allowlist[@]}" ||
    die "launcher $desktop_name is not in $ALLOWLIST and is not a documented menu exclusion"
done

# (d) the panel's launchers are a strict subset of the Dashboard favourites: the
# child must not get a route to an app the menu hides.
for entry in "${panel_launchers[@]}"; do
  list_contains "$entry" "${dashboard_favorites[@]}" ||
    die "panelLaunchers entry $entry is not present in dashboardFavorites"
done

# The system-app allowlist entry has no applications: reference in panel.js, so
# the check below skips it. That leaves the file manager unchecked, and dropping
# the preference silently removes both the Dashboard entry and the Super+E route.
list_contains "$PREFERRED_FILE_MANAGER" "${dashboard_favorites[@]}" ||
  die "panel.js dashboardFavorites is missing $PREFERRED_FILE_MANAGER; Dolphin is allowlisted and would be unreachable"
list_contains "$PREFERRED_FILE_MANAGER" "${panel_launchers[@]}" ||
  die "panel.js panelLaunchers is missing $PREFERRED_FILE_MANAGER; the panel file-manager shortcut would disappear"

# Every allowlisted application must be reachable from the Dashboard, otherwise
# finalization hides it and the child has no route to a launcher this project
# deliberately ships. Excludes the two documented system/power exceptions, which
# are reached by other means.
for entry in "${allowlist[@]}"; do
  if list_contains "$entry" "${MENU_EXCLUSIONS[@]}" ||
     list_contains "$entry" "${SYSTEM_APP_ALLOWLIST[@]}"; then
    continue
  fi
  reference="applications:${entry}"
  list_contains "$reference" "${dashboard_favorites[@]}" ||
    die "allowlisted application $entry is not in dashboardFavorites, so curation would hide it from the child"
done

printf '[launchers] %d dashboard favourites, %d panel launchers, %d allowlist entries agree.\n' \
  "${#dashboard_favorites[@]}" "${#panel_launchers[@]}" "${#allowlist[@]}"
