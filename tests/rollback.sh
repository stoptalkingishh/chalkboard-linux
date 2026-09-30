#!/usr/bin/env bash
# Behavioural tests for scripts/fedora/rollback.sh's file-restoration logic.
#
# rollback.sh is the documented last-resort recovery path, so a bug in it strands
# a device. Its real behaviour is the restore/remove loop over $BACKUP_DIR/files,
# which runs as root against absolute paths. The test drives the shipped script
# with CHALKBOARD_STATE_DIR pointed at a fixture tree and a PATH shim replacing
# the system commands, so nothing on the test machine is touched while the code
# under test stays the shipped code.
#
# Path convention: rollback.sh maps each backup path to an ABSOLUTE target as
# "/${backup#$BACKUP_DIR/files/}". To keep every write inside the fixture, each
# logical target P is stored as "$STATE/files$FIXTURE/P", so the absolute target
# resolves to "$FIXTURE/P". FIXTURE is a mktemp directory under /tmp, so
# "$STATE/files$FIXTURE" is "$STATE/files/tmp/tmp.XXXX".
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

failures=0
fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

FIXTURE=$(mktemp -d)
ROOT=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$ROOT"' EXIT

# ---- a shim directory whose commands record calls and change nothing ----
SHIM="$ROOT/shim"
mkdir -p "$SHIM"
for cmd in systemctl nmcli restorecon chage; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SHIM/$cmd"
  chmod +x "$SHIM/$cmd"
done
# The screen-time helper whose failure must not abort rollback. The single quotes
# are deliberate: the shim is written literally and expanded at run time.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "called\\n" >>"$SHIM_LOG"\nexit "${FAKE_SCREEN_TIME_STATUS:-0}"\n' \
  >"$SHIM/chalkboard-screen-time"
chmod +x "$SHIM/chalkboard-screen-time"

# rollback.sh resolves lib.sh and the helper by absolute path. Drop require_root
# and repoint both. Nothing else may change, or the restore logic stops being
# what is under test.
ROLLBACK=scripts/fedora/rollback.sh
REWRITTEN="$ROOT/rollback-under-test.sh"
sed -e '/^require_root$/d' \
  -e "s#/usr/local/libexec/chalkboard-screen-time#\$HELPER#g" \
  -e "s#^SCRIPT_DIR=.*#SCRIPT_DIR=\"$REPO_ROOT/scripts/fedora\"#" \
  "$ROLLBACK" >"$REWRITTEN"

# `diff` exits 1 when the files differ, which is the expected case here, and
# pipefail would abort the run before the count is checked. Tolerate it.
# The allowed rewrites are exactly: SCRIPT_DIR, require_root, and the two
# screen-time helper references. Anything else means the restore/remove logic is
# no longer what is under test, so fail loudly rather than report a green run
# that proved nothing.
allowed=$(diff <(cat "$ROLLBACK") <(cat "$REWRITTEN") | grep '^>' || true)
unexpected=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # The $HELPER literal is intentional: the rewritten script substitutes the
  # helper path at run time, and it must not expand here.
  # shellcheck disable=SC2016
  if [[ "$line" == *'SCRIPT_DIR='* || "$line" == *'require_root'* ||
        "$line" == *'$HELPER'* ]]; then
    continue
  fi
  unexpected=$((unexpected + 1))
  printf 'unexpected rewrite: %s\n' "$line" >&2
done <<<"$allowed"
if (( unexpected > 0 )); then
  fail "test harness rewrote $unexpected line(s) beyond the allowed substitutions"
  exit 1
fi

ROLLBACK_STATUS=0
ROLLBACK_ERR=''
ROLLBACK_OUT=''
run_rollback() {
  local state="$1" screen_time_status="$2" log="$ROOT/shim.log" status=0
  : >"$log"
  set +e
  HELPER="$SHIM/chalkboard-screen-time" \
  SHIM_LOG="$log" \
  FAKE_SCREEN_TIME_STATUS="$screen_time_status" \
  PATH="$SHIM:$PATH" \
  CHALKBOARD_STATE_DIR="$state" \
    bash "$REWRITTEN" >"$ROOT/out" 2>"$ROOT/err"
  status=$?
  set -e
  ROLLBACK_STATUS=$status
  ROLLBACK_ERR=$(cat "$ROOT/err")
  ROLLBACK_OUT=$(cat "$ROOT/out")
}

# Store a logical backup entry, mapping the absolute target back into $FIXTURE.
# rollback.sh derives BACKUP_DIR from STATE_DIR as "$STATE_DIR/backup" and then
# walks "$BACKUP_DIR/files", so a fixture state dir must contain backup/files.
new_state() { # new_state <name> -> echoes the STATE_DIR path
  local state="$ROOT/$1"
  mkdir -p "$state/backup/files"
  printf '%s' "$state"
}
put_backup() { # put_backup <state> <logical-absolute-path> [content]
  local state="$1" logical="$2" content="${3:-}"
  local dest
  dest="$state/backup/files$(p "$logical")"
  mkdir -p "$(dirname "$dest")"
  printf '%s' "$content" >"$dest"
}
put_marker() { # a .missing marker for a logical path
  local state="$1" logical="$2"
  mkdir -p "$(dirname "$state/backup/files$(p "$logical").missing")"
  : >"$state/backup/files$(p "$logical").missing"
}
# Logical paths are stated as they would appear on the device (/etc/...) and are
# transparently rebased onto the fixture, so the assertions below read naturally
# while every absolute write stays inside the fixture.
p() { printf '%s%s' "$FIXTURE" "$1"; }
# The absolute path rollback.sh will restore/remove for a logical entry.
target_of() { p "$1"; }

# ---- case 1: a screen-time force-release failure must not abort rollback ----
STATE=$(new_state s1)
put_backup "$STATE" /etc/chalkboard/original.conf 'original'
run_rollback "$STATE" 1
if [[ $ROLLBACK_STATUS -eq 0 ]]; then
  printf 'PASS  screen-time failure does not abort rollback\n'
else
  fail "screen-time failure aborted rollback (exit $ROLLBACK_STATUS): $ROLLBACK_ERR"
fi
if [[ "$ROLLBACK_OUT" == *"restoring files that existed before deployment"* ]]; then
  printf 'PASS  restoration still runs after a screen-time failure\n'
else
  fail "restoration was skipped after a screen-time failure: $ROLLBACK_OUT"
fi
if [[ "$ROLLBACK_ERR" == *"account expiry was NOT restored"* ]]; then
  printf 'PASS  the unrestored expiry is warned about explicitly\n'
else
  fail "no warning about the unrestored account expiry: $ROLLBACK_ERR"
fi
if grep -q called "$ROOT/shim.log"; then
  printf 'PASS  the screen-time helper was still attempted\n'
else
  fail 'the screen-time helper was never called'
fi

# ---- case 2: a .missing marker naming a directory must not abort the loop ----
# backup_file also records directories, so a marker can name one. `rm -f` fails
# on a directory and, under `set -e`, that would abort before the next removal.
STATE=$(new_state s2)
mkdir -p "$(target_of /etc/networkmanager/system-connections)"
put_marker "$STATE" /etc/networkmanager/system-connections
printf 'installed-by-chalkboard\n' >"$(target_of /etc/should-still-be-removed.conf)"
put_marker "$STATE" /etc/should-still-be-removed.conf 
run_rollback "$STATE" 0
if [[ $ROLLBACK_STATUS -eq 0 ]]; then
  printf 'PASS  a directory marker does not abort rollback\n'
else
  fail "a directory marker aborted rollback (exit $ROLLBACK_STATUS): $ROLLBACK_ERR"
fi
if [[ "$ROLLBACK_OUT" == *"configuration rollback complete"* ]]; then
  printf 'PASS  rollback runs to completion after a directory marker\n'
else
  fail "rollback did not run to completion: $ROLLBACK_OUT"
fi
if [[ ! -e "$(target_of /etc/should-still-be-removed.conf)" ]]; then
  printf 'PASS  removals after a directory marker still happen\n'
else
  fail 'a later removal was skipped after a directory marker'
fi
if [[ ! -d "$(target_of /etc/networkmanager/system-connections)" ]]; then
  printf 'PASS  the directory named by a marker is removed\n'
else
  fail 'the directory named by a marker was not removed'
fi

# ---- case 3: restoring must not widen a pre-existing 0700 parent ----
# On a real device this is /etc/NetworkManager/system-connections, mode 0700,
# holding stored Wi-Fi PSKs. Bare `install -d` there applied 0755.
STATE=$(new_state s3)
SECRET_PARENT="$FIXTURE/etc/NetworkManager/system-connections"
mkdir -p "$SECRET_PARENT"
chmod 0700 "$SECRET_PARENT"
put_backup "$STATE" /etc/NetworkManager/system-connections/home.nmconnection 'psk=secret'
run_rollback "$STATE" 0
mode=$(stat -c '%a' "$SECRET_PARENT")
if [[ "$mode" == 700 ]]; then
  printf 'PASS  a pre-existing 0700 parent keeps its mode (got %s)\n' "$mode"
else
  fail "rollback widened a 0700 parent to $mode"
fi
if [[ "$(cat "$SECRET_PARENT/home.nmconnection")" == 'psk=secret' ]]; then
  printf 'PASS  the backed-up connection file is restored\n'
else
  fail 'the backed-up connection file was not restored'
fi

# ---- case 4: a restore into a parent that does not exist yet ----
STATE=$(new_state s4)
put_backup "$STATE" /etc/brand-new/thing.conf 'content'
run_rollback "$STATE" 0
if [[ -f "$(target_of /etc/brand-new/thing.conf)" &&
      "$(cat "$(target_of /etc/brand-new/thing.conf)")" == content ]]; then
  printf 'PASS  a missing parent is created and the file restored\n'
else
  fail 'a restore into a missing parent did not work'
fi

# ---- case 5: a symlink marker is unlinked, not followed ----
STATE=$(new_state s5)
VICTIM="$FIXTURE/important.txt"
printf 'must survive\n' >"$VICTIM"
LINK="$FIXTURE/linked.conf"
ln -s "$VICTIM" "$LINK"
put_marker "$STATE" /linked.conf
run_rollback "$STATE" 0
if [[ -f "$VICTIM" && "$(cat "$VICTIM")" == 'must survive' ]]; then
  printf 'PASS  a symlink is unlinked without touching its target\n'
else
  fail 'rollback followed a symlink and damaged its target'
fi

# ---- case 6: no backup at all is refused ----
STATE="$ROOT/s6"; mkdir -p "$STATE"
run_rollback "$STATE" 0
if [[ $ROLLBACK_STATUS -ne 0 && "$ROLLBACK_ERR" == *"no Chalkboard backup"* ]]; then
  printf 'PASS  a missing backup tree is refused\n'
else
  fail "a missing backup tree was not refused (exit $ROLLBACK_STATUS): $ROLLBACK_ERR"
fi

# ---- case 7: no installed application was removed ----
STATE=$(new_state s7)
put_backup "$STATE" /etc/some.conf 'original'
run_rollback "$STATE" 0
if [[ "$ROLLBACK_OUT" == *"installed applications were retained"* ]]; then
  printf 'PASS  rollback keeps installed applications\n'
else
  fail "rollback no longer reports that applications are retained: $ROLLBACK_OUT"
fi

if (( failures > 0 )); then
  printf '\nrollback tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'Rollback restoration tests passed.\n'
