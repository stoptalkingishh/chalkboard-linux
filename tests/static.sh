#!/usr/bin/env bash

set -Eeuo pipefail

while IFS= read -r script; do
  bash -n "$script"
  shellcheck -x -P SCRIPTDIR "$script"
done < <(find scripts config -type f -name '*.sh' -print)

python3 -m json.tool config/fedora/vivaldi-policy.json >/dev/null

while IFS= read -r desktop_file; do
  desktop-file-validate "$desktop_file"
done < <(find config -type f -name '*.desktop' -print)

if grep -RIE '(password|passwd)[[:space:]]*=' config scripts; then
  printf 'Possible embedded password found.\n' >&2
  exit 1
fi

# Reject executable automation only. The separator-tolerant pattern covers
# "scratchjr", "Scratch Jr", "scratch-jr", and "scratch_jr". Documentation and
# future re-verification text belong in docs/ or tests/, which are not scanned.
# When all ScratchJr acceptance criteria pass, this check must be removed along
# with the launcher addition.
if grep -RIEi 'scratch[ _-]?jr' config scripts; then
  printf 'ScratchJr executable automation requires renewed trust review.\n' >&2
  exit 1
fi
