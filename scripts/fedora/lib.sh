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
