#!/usr/bin/env bash

set -Eeuo pipefail

# Both the curation writer and its verifier compare the same two sets with sort
# and comm. Pin the collation so a different locale cannot order them differently
# and report a false mismatch, or hide a real one.
export LC_ALL=C

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
  # CHALKBOARD_APPLICATION_DIRS lets the tests point this at a fixture tree. It is
  # read -a rather than a word-split array expansion so pathname expansion cannot
  # run: a value of '*' would otherwise silently scan the current directory.
  if [[ -n "${CHALKBOARD_APPLICATION_DIRS:-}" ]]; then
    local -a override=()
    read -r -a override <<<"$CHALKBOARD_APPLICATION_DIRS"
    # An override that names no existing directory would make the visible set
    # empty, and the curation writer would then wipe the denylist. Both callers
    # run as root, so refuse rather than silently disabling the control.
    ((${#override[@]} > 0)) || {
      printf 'CHALKBOARD_APPLICATION_DIRS is set but empty\n' >&2
      return 1
    }
    local found=0
    for dir in "${override[@]}"; do
      if [[ -d "$dir" ]]; then
        printf '%s\n' "$dir"
        found=1
      fi
    done
    (( found > 0 )) || {
      printf 'CHALKBOARD_APPLICATION_DIRS names no existing directory: %s\n' \
        "$CHALKBOARD_APPLICATION_DIRS" >&2
      return 1
    }
    return 0
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
# belongs to. Locate the applet first and the group afterwards.
#
# The applet variable is cleared at every containment boundary: kickerdash is also
# a containment plugin, and a containment-level plugin= line must not be
# attributed to whichever applet header happened to precede it. Without the reset,
# the curation writer would write hiddenApplications into the wrong applet.
find_kickerdash_applet() {
  local appletrc="$1"
  awk '
    /^\[Containments\]\[[0-9]+\]$/ { applet = ""; next }
    /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { applet = $0; next }
    $0 == "plugin=org.kde.plasma.kickerdash" && applet != "" { print applet; exit }
  ' "$appletrc"
}

# Prints "<containment> <applet>" numeric ids for the kickerdash applet.
#
# The curation writer has to address the applet as a KConfig group path, so it
# needs the two numbers out of the "[Containments][N][Applets][M]" header.
# Deriving them with bash parameter expansion is a trap: ${var#[Containments][}
# treats [Containments] as a glob character class, not as the literal text, and
# silently produced a mangled group name. That wrote hiddenApplications into a
# group the Dashboard never reads, while the verifier, which then matched the key
# anywhere in the file, reported the app menu as curated. Both sides have to use
# the same answer, so it lives here and is parsed with awk rather than globs.
find_kickerdash_ids() {
  local appletrc="$1"
  awk '
    /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
      containment = $0
      sub(/^\[Containments\]\[/, "", containment)
      sub(/\]\[Applets\]\[[0-9]+\]$/, "", containment)
      applet = $0
      sub(/^.*\[Applets\]\[/, "", applet)
      sub(/\]$/, "", applet)
      next
    }
    /^\[Containments\]\[[0-9]+\]$/ { containment = ""; applet = ""; next }
    $0 == "plugin=org.kde.plasma.kickerdash" && containment != "" {
      print containment, applet
      exit
    }
  ' "$appletrc"
}

# Prints the kickerdash applet's hiddenApplications value, or nothing if the key
# is absent from the kickerdash applet's own [Configuration][General] group.
#
# The key is only read while inside that group. The device config also carries
# legacy slash-separated groups such as
# [Containments/75/Applets/76][Configuration][General], and other applets carry
# their own groups; matching on the key alone read a decoy from one of those and
# let the verifier report the app menu as curated when the real group held
# nothing. Matching text anywhere after the applet header is not enough.
read_kickerdash_hidden() {
  local appletrc="$1" target
  target="$(find_kickerdash_applet "$appletrc")"
  [[ -n "$target" ]] || return 1
  awk -v target="$target" '
    $0 == target { found = 1; in_group = 0; next }
    found && $0 == target "[Configuration][General]" { in_group = 1; next }
    found && /^\[/ { in_group = 0; next }
    in_group && /^hiddenApplications=/ {
      sub(/^hiddenApplications=/, "")
      print
      exit
    }
  ' "$appletrc"
}
