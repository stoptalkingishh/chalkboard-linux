#!/usr/bin/env bash

retro_valid_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]
}

retro_valid_name() {
  local pattern="^[A-Za-z0-9][A-Za-z0-9 .,\"'()&:+_-]{0,79}$"
  [[ "$1" =~ $pattern ]]
}

retro_valid_executable() {
  local path="$1"
  local component
  local -a components

  [[ "$path" == drive_c/* ]] || return 1
  [[ "${path,,}" == *.exe ]] || return 1
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *\\* ]] || return 1
  IFS=/ read -r -a components <<<"$path"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
  done
}

retro_valid_sha256() {
  [[ "$1" =~ ^[0-9a-fA-F]{64}$ ]]
}

retro_write_desktop() {
  local name="$1"
  local id="$2"

  retro_valid_name "$name" && retro_valid_id "$id" || return 1
  printf '[Desktop Entry]\nType=Application\n'
  printf 'Name=%s\n' "$name"
  printf 'Comment=Parent-installed Windows game\n'
  printf 'Exec=/usr/local/libexec/chalkboard-retro-launch %s\n' "$id"
  printf 'Icon=applications-games\nTerminal=false\nCategories=Game;\n'
}

# Writes a root-readable source into the child's own directory tree as the
# child user. Running root install/cp into a child-writable path is a
# symlink-follow attack surface, so the write is performed without elevation.
retro_install_child_file() {
  local source="$1"
  local destination="$2"
  local parent

  parent="$(dirname -- "$destination")"
  install -d -o "$CHILD_USER" -g "$CHILD_USER" -m 0700 -- "$parent"
  runuser -u "$CHILD_USER" -- cp -f -- "$source" "$destination"
}
