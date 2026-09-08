#!/usr/bin/env bash

set -Eeuo pipefail

readonly RETRO_LIB=/usr/local/libexec/chalkboard-retro-lib
readonly RUNTIME_DIR=/usr/local/share/chalkboard

die() {
  printf '[chalkboard-retro] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -r "$RETRO_LIB" ]] || die "framework is not installed"
[[ "$(stat -c %u:%a -- "$RETRO_LIB")" == 0:644 ]] || die "framework permissions are unsafe"
# shellcheck source=retro-lib.sh
source "$RETRO_LIB"
[[ $# -eq 1 ]] || die "a single registered game ID is required"
retro_valid_id "$1" || die "invalid game ID"

child_file="$RUNTIME_DIR/retro-child-user"
[[ "$(stat -c %u:%a -- "$child_file" 2>/dev/null)" == 0:644 ]] || die "child identity permissions are unsafe"
child_user="$(cat "$child_file" 2>/dev/null)" || die "child account is not configured"
[[ "$(id -un)" == "$child_user" ]] || die "this launcher is only for the configured child account"
child_home="$(getent passwd "$child_user" | cut -d: -f6)"
[[ "$HOME" == "$child_home" ]] || die "unexpected home directory"

game_dir="$RUNTIME_DIR/retro-games/$1"
[[ -d "$game_dir" && ! -L "$game_dir" ]] || die "game is not registered"
[[ -r "$game_dir/executable" ]] || die "game registration is incomplete"
[[ "$(stat -c %u:%a -- "$game_dir")" == 0:755 ]] || die "registration permissions are unsafe"
[[ "$(stat -c %u:%a -- "$game_dir/executable")" == 0:644 ]] || \
  die "executable metadata permissions are unsafe"
IFS= read -r executable <"$game_dir/executable"
retro_valid_executable "$executable" || die "registered executable is invalid"

prefix="$child_home/.local/share/chalkboard/retro/$1/prefix"
[[ -d "$prefix" && ! -L "$prefix" ]] || die "Wine prefix is missing"
resolved_prefix="$(realpath -e -- "$prefix")" || die "cannot resolve Wine prefix"
resolved_executable="$(realpath -e -- "$prefix/$executable")" || die "game executable is missing"
[[ "$resolved_executable" == "$resolved_prefix"/* && -f "$resolved_executable" ]] || \
  die "game executable escapes its Wine prefix"

exec env WINEPREFIX="$resolved_prefix" WINEDLLOVERRIDES=winemenubuilder.exe=d \
  /usr/bin/wine "$resolved_executable"
