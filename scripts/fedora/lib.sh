#!/usr/bin/env bash

set -Eeuo pipefail

STATE_DIR="${CHALKBOARD_STATE_DIR:-/var/lib/chalkboard}"
BACKUP_DIR="$STATE_DIR/backup"

log() {
  printf '[chalkboard] %s\n' "$*"
}

die() {
  printf '[chalkboard] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run this command as root, for example with sudo"
}

require_fedora() {
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  # Distribution-provided operating system metadata.
  source /etc/os-release
  [[ "${ID:-}" == fedora ]] || die "this installer currently supports Fedora only"
  [[ "${VERSION_ID:-}" == 43 ]] || die "this release is tested only on Fedora 43"
}

validate_nextdns_profile() {
  [[ "$1" =~ ^[0-9a-f]{6}$ ]]
}

backup_file() {
  local path="$1"
  local backup="$BACKUP_DIR/files$path"

  if [[ -e "$backup" || -e "$backup.missing" ]]; then
    return
  fi

  install -d -m 0700 "$(dirname "$backup")"
  if [[ -e "$path" || -L "$path" ]]; then
    cp -a "$path" "$backup"
  else
    touch "$backup.missing"
  fi
}

install_managed_file() {
  local source="$1"
  local destination="$2"
  local mode="${3:-0644}"

  backup_file "$destination"
  install -D -o root -g root -m "$mode" "$source" "$destination"
}

child_home() {
  getent passwd "$1" | cut -d: -f6
}

# The XDG application directories the child's Application Dashboard reads. The
# Flatpak export directory is absent unless a system Flatpak is installed, and
# the child's own directory before first login, so both are optional.
child_application_dirs() {
  local child_home="$1"
  local dir
  # CHALKBOARD_APPLICATION_DIRS lets the tests point this at a fixture tree. The
  # production path below is unaffected; only the input list changes.
  if [[ -n "${CHALKBOARD_APPLICATION_DIRS:-}" ]]; then
    local saved=$IFS
    IFS=' '
    # shellcheck disable=SC2206  # deliberate word splitting into the list
    local -a override=($CHALKBOARD_APPLICATION_DIRS)
    IFS=$saved
    for dir in "${override[@]}"; do
      [[ -d "$dir" ]] && printf '%s\n' "$dir"
    done
    return
  fi
  for dir in \
    /usr/share/applications \
    /usr/local/share/applications \
    /var/lib/flatpak/exports/share/applications \
    "$child_home/.local/share/applications"; do
    [[ -d "$dir" ]] && printf '%s\n' "$dir"
  done
}

# Every application entry the child's Application Dashboard can show, one desktop
# file basename per line, in directory-then-name order.
#
# This is the single definition of "visible to the child". The curation writer
# (curate-app-menu.sh) and the verifier (check-app-menu.sh) both call it, because
# when they each enumerated independently the verifier drifted: it omitted the
# NoDisplay filter and so expected 150-odd KDE settings modules to be in the
# denylist that curation correctly never writes. A threshold check hid that; an
# exact comparison did not.
#
# Entries are excluded when they are not Type=Application, or when NoDisplay or
# Hidden is true. Most KDE control-centre modules are NoDisplay=true: they are
# reachable from the settings UI, not from the application menu.
child_visible_applications() {
  local child_home="$1" entry
  local -a dirs=()
  mapfile -t dirs < <(child_application_dirs "$child_home")
  ((${#dirs[@]} > 0)) || return 0
  while IFS= read -r -d '' entry; do
    [[ "$entry" == *.desktop ]] || continue
    grep -q '^Type=Application' "$entry" 2>/dev/null || continue
    if grep -qE '^(NoDisplay|Hidden)=true' "$entry" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "${entry##*/}"
  done < <(find "${dirs[@]}" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null | sort -zu)
}

# The allowlist entries, one per line, with comments and blank lines removed and
# CR stripped so a checkout with CRLF endings still matches.
read_allowlist() {
  local file="$1"
  [[ -r "$file" ]] || return 1
  tr -d '\r' <"$file" | grep -E '^[^#[:space:]]'
}

# Prints "<containment> <applet>" for the kickerdash applet.
#
# Plasma writes the applet header, then plugin=, and only then the applet's
# [Configuration][General] group, so the plugin line arrives BEFORE the group it
# belongs to. Locate the applet first and the group afterwards, tracking group
# membership explicitly rather than by proximity.
find_kickerdash_applet() {
  local appletrc="$1"
  awk '
    /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { applet = $0; next }
    $0 == "plugin=org.kde.plasma.kickerdash" { print applet; exit }
  ' "$appletrc"
}

# Prints the kickerdash applet's hiddenApplications value, or nothing if the key
# is absent. Uses the containment/applet identifiers rather than a plain text
# search, so the legacy slash-separated groups the device config also carries are
# not mistaken for the real one.
read_kickerdash_hidden() {
  local appletrc="$1" target
  target="$(find_kickerdash_applet "$appletrc")"
  [[ -n "$target" ]] || return 1
  awk -v target="$target" '
    function reset() { group = "" }
    $0 == target { found = 1; applet = $0; reset(); next }
    found && /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]\[Configuration\]\[General\]$/ {
      group = applet
      next
    }
    found && /^\[/ { reset(); next }
    found && /^hiddenApplications=/ {
      sub(/^hiddenApplications=/, "")
      print
      exit
    }
  ' "$appletrc"
}
