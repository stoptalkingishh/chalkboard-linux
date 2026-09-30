#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/fedora/retro-lib.sh
source "$SCRIPT_DIR/../scripts/fedora/retro-lib.sh"

expect_valid() {
  "$@" || { printf 'Expected valid: %q\n' "$*" >&2; exit 1; }
}

expect_invalid() {
  # Every retro_valid_* predicate is a bare [[ ]] test and retro_write_desktop
  # dies, so the code that must reject the input is always exactly 1. Assert
  # that literally: the old `if "$@"; then` form could not tell rejection from
  # "function missing" (127), which meant deleting a predicate from
  # retro-lib.sh turned its own test into a silent pass.
  local st=0
  "$@" >/dev/null 2>&1 || st=$?
  if [[ $st -ne 1 ]]; then
    printf 'expected %q to be rejected with exit 1, got %s\n' "$*" "$st" >&2
    exit 1
  fi
}

expect_valid retro_valid_id game-2
expect_invalid retro_valid_id ../game
expect_invalid retro_valid_id 'game;sh'
expect_invalid retro_valid_id "$(printf 'a%.0s' {1..41})"

expect_valid retro_valid_name 'Parents Game (1998)'
expect_invalid retro_valid_name $'Game\nExec=sh'
expect_invalid retro_valid_name 'Game; Exec=sh'

expect_valid retro_valid_executable 'drive_c/Program Files/Game/Game.exe'
expect_valid retro_valid_executable 'drive_c/GAME.EXE'
expect_invalid retro_valid_executable '/tmp/game.exe'
expect_invalid retro_valid_executable 'drive_c/../escape.exe'
expect_invalid retro_valid_executable 'drive_c/game.exe --flag'
expect_invalid retro_valid_executable 'drive_c\game.exe'

expect_valid retro_valid_sha256 "$(printf 'a%.0s' {1..64})"
expect_invalid retro_valid_sha256 "$(printf 'a%.0s' {1..63})"
expect_invalid retro_valid_sha256 "$(printf 'z%.0s' {1..64})"

desktop="$(retro_write_desktop 'Parents Game' game-2)"
grep -Fxq 'Name=Parents Game' <<<"$desktop"
grep -Fxq 'Exec=/usr/local/libexec/chalkboard-retro-launch game-2' <<<"$desktop"
expect_invalid retro_write_desktop $'Game\nExec=/bin/sh' game-2

printf 'Retro validation tests passed.\n'
