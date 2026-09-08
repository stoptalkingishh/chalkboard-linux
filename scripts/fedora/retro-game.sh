#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_DIR=/usr/local/share/chalkboard/retro-games
readonly WINE_DESKTOP_MASK="$SCRIPT_DIR/../../config/fedora/retro-wine-hidden.desktop"
readonly -a WINE_DESKTOP_FILES=(
  wine-mime-msi.desktop wine-notepad.desktop wine-oleview.desktop
  wine-regedit.desktop wine-uninstaller.desktop wine-wineboot.desktop
  wine-winecfg.desktop wine-winefile.desktop wine-winemine.desktop
  wine-winhelp.desktop wine-wordpad.desktop wine.desktop
)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=retro-lib.sh
source "$SCRIPT_DIR/retro-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  retro-game.sh install --id ID --name NAME --installer ABSOLUTE_PATH \
    --sha256 SHA256 --executable drive_c/RELATIVE/PATH.exe --owned-media
  retro-game.sh verify ID
  retro-game.sh uninstall ID

The parent must supply lawfully owned media and its recorded SHA-256 digest.
Installation must be supervised in the active child session.
EOF
}

load_child() {
  [[ -r "$STATE_DIR/child-user" ]] || die "run the main Chalkboard deployment first"
  CHILD_USER="$(<"$STATE_DIR/child-user")"
  getent passwd "$CHILD_USER" >/dev/null || die "configured child account does not exist"
  [[ "$(id -u "$CHILD_USER")" -ge 1000 ]] || die "refusing to use a system account"
  CHILD_HOME="$(child_home "$CHILD_USER")"
  [[ -d "$CHILD_HOME" && ! -L "$CHILD_HOME" ]] || die "child home is missing or unsafe"
}

install_framework() {
  local child_user_file desktop_file destination

  log "installing Wine from Fedora repositories"
  dnf -y --disablerepo='*' --enablerepo=fedora --enablerepo=updates install wine
  install_managed_file "$SCRIPT_DIR/retro-lib.sh" /usr/local/libexec/chalkboard-retro-lib 0644
  install_managed_file "$SCRIPT_DIR/retro-launch.sh" /usr/local/libexec/chalkboard-retro-launch 0755
  child_user_file="$(mktemp)"
  printf '%s\n' "$CHILD_USER" >"$child_user_file"
  install_managed_file "$child_user_file" /usr/local/share/chalkboard/retro-child-user 0644
  rm -f "$child_user_file"

  for desktop_file in "${WINE_DESKTOP_FILES[@]}"; do
    destination="$CHILD_HOME/.local/share/applications/$desktop_file"
    backup_file "$destination"
    retro_install_child_file "$WINE_DESKTOP_MASK" "$destination"
  done
}

run_installer() {
  local installer="$1"
  local prefix="$2"
  local uid runtime wayland_socket candidate x_number xauthority found_display=0
  local -a session_env

  uid="$(id -u "$CHILD_USER")"
  runtime="/run/user/$uid"
  [[ -S "$runtime/bus" ]] || die "the child must have an active graphical session"
  session_env=(
    "HOME=$CHILD_HOME"
    "USER=$CHILD_USER"
    "LOGNAME=$CHILD_USER"
    "PATH=/usr/local/bin:/usr/bin:/bin"
    "XDG_RUNTIME_DIR=$runtime"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime/bus"
    "WINEPREFIX=$prefix"
    "WINEDLLOVERRIDES=winemenubuilder.exe=d"
  )
  wayland_socket=''
  for candidate in "$runtime"/wayland-[0-9]*; do
    if [[ -S "$candidate" ]]; then
      wayland_socket="$(basename -- "$candidate")"
      break
    fi
  done
  if [[ -n "$wayland_socket" ]]; then
    session_env+=("WAYLAND_DISPLAY=$wayland_socket")
    found_display=1
  fi
  for candidate in /tmp/.X11-unix/X[0-9]*; do
    [[ -S "$candidate" ]] || continue
    x_number="${candidate##*/X}"
    session_env+=("DISPLAY=:$x_number")
    for xauthority in "$runtime"/xauth_*; do
      if [[ -f "$xauthority" && ! -L "$xauthority" ]] && \
        [[ "$(stat -c %u -- "$xauthority")" == "$uid" ]]; then
        session_env+=("XAUTHORITY=$xauthority")
        break
      fi
    done
    found_display=1
    break
  done
  if [[ $found_display -eq 0 ]]; then
    die "no supported child display socket was found"
  fi

  log "starting the parent-supplied installer as the unprivileged child user"
  runuser -u "$CHILD_USER" -- env -i "${session_env[@]}" /usr/bin/wine "$installer"
}

verify_game() {
  local id="$1"
  local game_dir prefix executable resolved_prefix resolved_executable launcher

  retro_valid_id "$id" || die "invalid game ID"
  game_dir="$REGISTRY_DIR/$id"
  launcher="$CHILD_HOME/.local/share/applications/chalkboard-retro-$id.desktop"
  [[ -d "$game_dir" && ! -L "$game_dir" ]] || die "$id is not registered"
  [[ "$(stat -c %u:%a -- "$game_dir")" == 0:755 ]] || die "registration permissions are unsafe"
  IFS= read -r executable <"$game_dir/executable"
  [[ "$(stat -c %u:%a -- "$game_dir/executable")" == 0:644 ]] || \
    die "executable metadata permissions are unsafe"
  retro_valid_executable "$executable" || die "stored executable is invalid"
  prefix="$CHILD_HOME/.local/share/chalkboard/retro/$id/prefix"
  resolved_prefix="$(realpath -e -- "$prefix")" || die "Wine prefix is missing"
  resolved_executable="$(realpath -e -- "$prefix/$executable")" || die "game executable is missing"
  [[ "$resolved_executable" == "$resolved_prefix"/* && -f "$resolved_executable" ]] || \
    die "game executable escapes its Wine prefix"
  [[ -f "$launcher" && ! -L "$launcher" ]] || die "child launcher is missing"
  grep -Fxq "Exec=/usr/local/libexec/chalkboard-retro-launch $id" "$launcher" || \
    die "child launcher command is invalid"
  [[ -x /usr/local/libexec/chalkboard-retro-launch ]] || die "launcher wrapper is missing"
  [[ "$(stat -c %u:%a -- /usr/local/libexec/chalkboard-retro-launch)" == 0:755 ]] || \
    die "launcher wrapper permissions are unsafe"
  [[ "$(stat -c %u:%a -- /usr/local/libexec/chalkboard-retro-lib)" == 0:644 ]] || \
    die "launcher library permissions are unsafe"
  [[ "$(stat -c %u:%a -- /usr/local/share/chalkboard/retro-child-user)" == 0:644 ]] || \
    die "launcher child identity permissions are unsafe"
  grep -Fxq "$CHILD_USER" /usr/local/share/chalkboard/retro-child-user || \
    die "launcher child identity is invalid"
  rpm -q wine >/dev/null || die "Wine is not installed"
  log "$id registration is valid; runtime compatibility is not asserted"
}

install_game() {
  local id='' name='' installer='' expected_hash='' executable='' owned_media=0
  local actual_hash prefix game_dir launcher installer_copy temporary_desktop=''
  local resolved_prefix resolved_executable completed=0 recorded_hash=''

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id|--name|--installer|--sha256|--executable)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        case "$1" in
          --id) id="$2" ;;
          --name) name="$2" ;;
          --installer) installer="$2" ;;
          --sha256) expected_hash="${2,,}" ;;
          --executable) executable="$2" ;;
        esac
        shift 2
        ;;
      --owned-media) owned_media=1; shift ;;
      *) die "unknown install option: $1" ;;
    esac
  done

  retro_valid_id "$id" || die "ID must be 1-40 lowercase letters, numbers, or hyphens"
  retro_valid_name "$name" || die "name contains unsupported characters or is too long"
  retro_valid_sha256 "$expected_hash" || die "a 64-character SHA-256 digest is required"
  retro_valid_executable "$executable" || die "executable must be a safe drive_c path ending in .exe"
  [[ $owned_media -eq 1 ]] || die "--owned-media is required; only lawfully owned media may be used"
  [[ "$installer" == /* ]] || die "installer path must be absolute"
  installer="$(realpath -e -- "$installer")" || die "installer does not exist"
  [[ -f "$installer" && ! -L "$installer" ]] || die "installer must resolve to a regular file"
  actual_hash="$(sha256sum -- "$installer" | cut -d' ' -f1)"
  [[ "$actual_hash" == "$expected_hash" ]] || die "installer SHA-256 does not match"

  game_dir="$REGISTRY_DIR/$id"
  launcher="$CHILD_HOME/.local/share/applications/chalkboard-retro-$id.desktop"
  prefix="$CHILD_HOME/.local/share/chalkboard/retro/$id/prefix"
  if [[ -d "$game_dir" ]]; then
    install_framework
    recorded_hash="$(cat "$game_dir/installer-sha256" 2>/dev/null || true)"
    [[ -n "$recorded_hash" ]] || die "registered digest is missing"
    [[ "$recorded_hash" == "$actual_hash" ]] || \
      die "supplied installer no longer matches the registered digest"
    verify_game "$id"
    log "$id is already installed; uninstall it before replacing it"
    return
  fi
  [[ ! -e "$prefix" && ! -L "$prefix" ]] || die "unregistered prefix already exists at $prefix"
  [[ ! -e "$launcher" && ! -L "$launcher" ]] || die "an unregistered launcher already exists at $launcher"

  install_framework
  install -d -o root -g root -m 0700 "$STATE_DIR/retro/backups"
  install -d -o root -g root -m 0755 "$REGISTRY_DIR"
  install -d -o root -g root -m 0711 "$STATE_DIR/retro/tmp"
  install -d -o "$CHILD_USER" -g "$CHILD_USER" -m 0700 "$(dirname "$prefix")" "$prefix"
  installer_copy="$(mktemp "$STATE_DIR/retro/tmp/chalkboard-retro-installer.XXXXXX.exe")"
  install -o root -g root -m 0444 "$installer" "$installer_copy"
  cleanup_failed_install() {
    rm -f -- "$installer_copy"
    [[ -z "$temporary_desktop" ]] || rm -f -- "$temporary_desktop"
    if [[ $completed -eq 0 ]]; then
      rm -f -- "$launcher"
      rm -rf -- "$game_dir" "${prefix:?}"
    fi
  }
  trap cleanup_failed_install EXIT INT TERM
  run_installer "$installer_copy" "$prefix"
  rm -f -- "$installer_copy"

  resolved_prefix="$(realpath -e -- "$prefix")" || die "installer did not create a Wine prefix"
  resolved_executable="$(realpath -e -- "$prefix/$executable")" || die "configured executable was not installed"
  [[ "$resolved_executable" == "$resolved_prefix"/* && -f "$resolved_executable" ]] || \
    die "configured executable escapes its Wine prefix"

  install -d -o root -g root -m 0755 "$game_dir"
  printf '%s\n' "$executable" >"$game_dir/executable"
  printf '%s\n' "$actual_hash" >"$game_dir/installer-sha256"
  chmod 0644 "$game_dir/executable" "$game_dir/installer-sha256"
  temporary_desktop="$(mktemp)"
  retro_write_desktop "$name" "$id" >"$temporary_desktop"
  chmod 0644 "$temporary_desktop"
  retro_install_child_file "$temporary_desktop" "$launcher"
  rm -f "$temporary_desktop"
  restorecon -RF "$game_dir" "$prefix" "$launcher" /usr/local/libexec 2>/dev/null || true
  verify_game "$id"
  completed=1
  trap - EXIT INT TERM
  log "installation registered; the parent must now test the game before child use"
}

uninstall_game() {
  local id="$1"
  local game_dir prefix launcher backup

  retro_valid_id "$id" || die "invalid game ID"
  game_dir="$REGISTRY_DIR/$id"
  prefix="$CHILD_HOME/.local/share/chalkboard/retro/$id"
  launcher="$CHILD_HOME/.local/share/applications/chalkboard-retro-$id.desktop"
  [[ -d "$game_dir" && ! -L "$game_dir" ]] || die "$id is not registered"
  install -d -o root -g root -m 0700 "$STATE_DIR/retro/backups"
  backup="$(mktemp -d "$STATE_DIR/retro/backups/$id-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  cp -a -- "$game_dir" "$backup/registration"
  [[ ! -e "$prefix" || -L "$prefix" ]] || cp -a -- "$prefix" "$backup/game-data"
  [[ ! -e "$launcher" || -L "$launcher" ]] || cp -a -- "$launcher" "$backup/launcher.desktop"
  rm -f -- "$launcher"
  rm -rf -- "$game_dir" "${prefix:?}"
  log "$id removed; local backup retained at $backup"
}

require_root
require_fedora
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
command="$1"
shift
load_child
case "$command" in
  install) install_game "$@" ;;
  verify) [[ $# -eq 1 ]] || die "verify requires one game ID"; verify_game "$1" ;;
  uninstall) [[ $# -eq 1 ]] || die "uninstall requires one game ID"; uninstall_game "$1" ;;
  -h|--help|help) usage ;;
  *) usage >&2; die "unknown command: $command" ;;
esac
