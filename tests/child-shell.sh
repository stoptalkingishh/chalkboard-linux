#!/usr/bin/env bash
# The single-quoted strings below are commands for the pty session, not for this
# shell, so their $variables must not be expanded here.
# shellcheck disable=SC2016
# Behavioural tests for scripts/fedora/child-shell.sh.
#
# The wrapper is a speed bump for a curious child, not a security boundary, and
# the tests assert that distinction rather than blurring it: several cases below
# assert that a limit does NOT hold, because pretending otherwise in a test would
# be the same mistake as pretending otherwise in the documentation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SHELL_SRC=scripts/fedora/child-shell.sh
failures=0
fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

[[ -r "$SHELL_SRC" ]] || {
  printf 'cannot read %s\n' "$SHELL_SRC" >&2
  exit 1
}

# The wrapper's limits are observable in the environment it hands to the shell it
# execs, so each case runs it with a probe shell in place of bash and inspects
# what the probe saw. That exercises the real code path rather than a copy of it.
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
# The session runs as the child, so the driver and the results file must be
# reachable by it. The directory is scratch space under a private mktemp path.
chmod 0755 "$probe_dir"
account_file="$probe_dir/child-account"
: >"$account_file"
chmod 0666 "$account_file"
: >"$probe_dir/out"
chmod 0666 "$probe_dir/out"

# The wrapper is a login shell, so it execs a real interactive bash and refuses
# to run without a terminal. Driving it therefore means giving it a pty, which is
# also the realistic case. A pty is allocated with Python's pty module rather than
# util-linux's script(1): script(1) was absent from a Fedora 43 image that
# util-linux was installed into, so depending on it would be a silent gap.
cat >"$probe_dir/drive.py" <<'DRIVER'
#!/usr/bin/env python3
"""Run a command on a pty, forward this process's stdin into it, and collect
lines the session prints that start with RESULT.

The wrapper is a login shell, so it needs a terminal, and the session it starts
reads commands from that terminal. This process therefore has to move its own
stdin into the pty; feeding the pty directly would be simpler but then the child
session would have nothing to read.
"""
import os
import pty
import select
import subprocess
import sys
import time

out_path = sys.argv[1]
command = sys.argv[2:]

master, slave = pty.openpty()
proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)

stdin_fd = sys.stdin.fileno()
os.set_blocking(stdin_fd, False)
collected = []
# Let the session finish starting before feeding it, or the first commands can be
# dropped while bash is still reading its startup files.
time.sleep(1.0)
# An overall deadline, so a session that never exits fails the test instead of
# hanging it. A hanging test is worse than a failing one: it blocks everything
# behind it and says nothing.
hard_deadline = time.time() + 30
# Drain until the child exits and the pty has nothing left. Stopping as soon as
# the process exits loses whatever was still buffered, which silently turned the
# PATH, HISTFILE, umask and ulimit assertions into passes and failures at random.
drain_deadline = None
while True:
    if time.time() > hard_deadline:
        proc.kill()
        break
    if proc.poll() is not None:
        if drain_deadline is None:
            drain_deadline = time.time() + 3.0
        if time.time() > drain_deadline:
            break
    readable, _, _ = select.select([master, stdin_fd], [], [], 0.2)
    for fd in readable:
        if fd == master:
            try:
                data = os.read(master, 8192)
            except OSError:
                data = b""
            if not data:
                proc.terminate()
                break
            for line in data.decode("utf-8", "replace").splitlines():
                if line.startswith("RESULT "):
                    collected.append(line[len("RESULT "):])
        else:
            if proc.poll() is not None:
                continue
            try:
                data = os.read(stdin_fd, 4096)
            except (BlockingIOError, OSError):
                continue
            if data:
                os.write(master, data)

os.close(master)
if collected:
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(collected) + "\n")
# Report a non-zero status when the session produced nothing, so the caller can
# tell "the wrapper refused" from "the wrapper ran but we saw nothing".
sys.exit(proc.wait() if proc.poll() is None else proc.returncode)
DRIVER
chmod 0755 "$probe_dir/drive.py"

run_wrapper() { # run_wrapper <user>
  local user="$1" out="$probe_dir/out"
  # Truncate rather than remove, and make it writable: the session writes it as
  # the child, while this directory is root-owned and mode 0700.
  : >"$out"; chmod 0666 "$out"
  local var
  {
    printf 'printf "RESULT PATH=%%s\\n" "$PATH"\n'
    printf 'printf "RESULT HISTFILE=%%s\\n" "$HISTFILE"\n'
    printf 'printf "RESULT RESTRICTED=%%s\\n" "${CHALKBOARD_RESTRICTED_SHELL:-unset}"\n'
    for var in LD_PRELOAD PYTHONPATH PERL5LIB BASH_ENV; do
      printf 'printf "RESULT %s=%%s\\n" "${%s+set}"\n' "$var" "$var"
    done
    # IFS is reported by value, not by whether it is set: bash always sets it.
    printf 'printf "RESULT IFS=%%q\\n" "$IFS"\n'
    printf 'printf "RESULT ulimit_cpu=%%s\\n" "$(ulimit -t)"\n'
    printf 'printf "RESULT ulimit_procs=%%s\\n" "$(ulimit -u)"\n'
    printf 'printf "RESULT ulimit_open=%%s\\n" "$(ulimit -n)"\n'
    printf 'printf "RESULT ulimit_file=%%s\\n" "$(ulimit -f)"\n'
    printf 'printf "RESULT umask=%%s\\n" "$(umask)"\n'
    printf 'exit\n'
  } | run_as "$user" python3 "$probe_dir/drive.py" "$out" \
        bash "$(realpath "$SHELL_SRC")" >"$probe_dir/tty.log" 2>&1
  # -s, not -f: the file is pre-created, so its mere existence proves nothing.
  # An empty file means the session never reported and every assertion below
  # would pass without having observed anything.
  [[ -s "$out" ]]
}

# Run the wrapper with the environment variables it is meant to clear actually set,
# and confirm none of them reach the session.
run_hostile_env() { # run_hostile_env <user>
  local user="$1" out="$probe_dir/hostile"
  : >"$out"; chmod 0666 "$out"
  {
    printf 'printf "RESULT PYTHONPATH=%%s\\n" "${PYTHONPATH-<unset>}"\n'
    printf 'printf "RESULT PERL5LIB=%%s\\n" "${PERL5LIB-<unset>}"\n'
    printf 'printf "RESULT BASH_ENV=%%s\\n" "${BASH_ENV-<unset>}"\n'
    printf 'printf "RESULT LD_PRELOAD=%%s\\n" "${LD_PRELOAD-<unset>}"\n'
    printf 'exit\n'
  } | run_as "$user" \
        env PYTHONPATH=/nonexistent PERL5LIB=/nonexistent \
            BASH_ENV=/nonexistent LD_PRELOAD=/nonexistent.so \
        python3 "$probe_dir/drive.py" "$out" \
        bash "$(realpath "$SHELL_SRC")" >"$probe_dir/hostile.log" 2>&1
  # -s, not -f: see run_wrapper. An empty result means the hostile run never
  # produced observations, and the caller would read that as "nothing leaked".
  [[ -s "$out" ]]
}

# Run a command as a specific account, dropping privileges when the test is root,
# because the wrapper refuses to run as root and for a system account.
run_as() { # run_as <user> <command...>
  local user="$1"
  shift
  if [[ "$(id -u)" -eq 0 && "$user" != root ]]; then
    runuser -u "$user" -- env \
      HOME="$(getent passwd "$user" | cut -d: -f6)" \
      TERM=dumb \
      CHALKBOARD_CHILD_ACCOUNT_FILE="$account_file" \
      "$@"
  else
    env TERM=dumb CHALKBOARD_CHILD_ACCOUNT_FILE="$account_file" "$@"
  fi
}

# The wrapper's account checks are part of what is being tested, so the positive
# assertions need an account that is genuinely eligible: a real unprivileged
# account that is not in wheel or sudo. On a developer machine or CI runner that
# is often the current user; where it is not, the refusals and the documentation
# assertions below still run rather than the whole file skipping.
eligible_account() {
  local candidate
  for candidate in "${CHILD_UNDER_TEST:-chalkboard}" "$(id -un)"; do
    id "$candidate" >/dev/null 2>&1 || continue
    [[ "$(id -u "$candidate")" -ge 1000 ]] || continue
    id -nG "$candidate" | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$' && continue
    printf '%s' "$candidate"
    return 0
  done
  return 1
}

out="$probe_dir/out"
got() { sed -n "s/^$1=//p" "$out"; }

if probe_user="$(eligible_account)"; then
  printf '%s\n' "$probe_user" >"$account_file"
  echo "testing the child shell wrapper as $probe_user"

  if run_wrapper "$probe_user"; then
    printf 'PASS  the wrapper starts an interactive shell for the child account\n'
  else
    fail 'the wrapper did not reach the shell'
    sed 's/^/      /' "$probe_dir/tty.log" | head -5
  fi

  if [[ "$(got RESTRICTED)" == 1 ]]; then
    printf 'PASS  the shell is marked as restricted\n'
  else
    fail 'the shell is not marked as restricted'
  fi

  # The wrappers that matter for a launched program. IFS is deliberately absent
  # from this list: an interactive bash always defines it, so "is it set" is not
  # the question. It is asserted separately against bash's default below.
  cleared=1
  for var in LD_PRELOAD PYTHONPATH PERL5LIB BASH_ENV; do
    [[ "$(got "$var")" == set ]] && {
      fail "$var survived into the shell"
      cleared=0
    }
  done
  (( cleared )) && printf 'PASS  interpreter and loader environment variables are cleared\n'

  # Now set them on the way in and confirm the wrapper removes them. Without this
  # the assertion above is vacuous: a variable that was never set cannot survive.
  if run_hostile_env "$probe_user"; then
    hostile="$probe_dir/hostile"
    leaked=0
    for var in PYTHONPATH PERL5LIB BASH_ENV LD_PRELOAD; do
      # A variable the session never reported is not a variable that failed to
      # leak; it is an observation we did not make. Fail rather than pass.
      if ! grep -q "^$var=" "$hostile"; then
        fail "$var was not reported, so its absence proves nothing"
        leaked=1
        continue
      fi
      value="$(sed -n "s/^$var=//p" "$hostile")"
      if [[ -n "$value" && "$value" != '<unset>' ]]; then
        fail "$var reached the session with a caller-supplied value: $value"
        leaked=1
      fi
    done
    (( leaked == 0 )) &&
      printf 'PASS  caller-supplied environment variables are removed, not merely absent\n'
  else
    fail 'the wrapper did not start with a hostile environment set'
  fi

  # IFS must be bash's own default, not a value the caller chose. bash sets it
  # itself, so the only way a caller's value survives is if the wrapper failed to
  # clear it before exec.
  # %q renders bash's default IFS as $' \t\n'. Build the same string rather
  # than comparing against a literal: a command substitution would eat the
  # trailing newline and make this fail for the right reason at the wrong place.
  expected_ifs=$(printf '%s' "\$' \\t\\n'")
  if [[ "$(got IFS)" == "$expected_ifs" ]]; then
    printf 'PASS  IFS is the shell default rather than a caller-supplied value\n'
  else
    fail "IFS was not reset to the shell default: got $(got IFS) want $expected_ifs"
  fi

  if [[ "$(got PATH)" == '/usr/bin:/bin' ]]; then
    printf 'PASS  PATH is pinned to the system directories\n'
  else
    fail "PATH was not pinned: $(got PATH)"
  fi

  if [[ "$(got HISTFILE)" == /dev/null ]]; then
    printf 'PASS  no shell history file is used\n'
  else
    fail "history file was not disabled: $(got HISTFILE)"
  fi

  case "$(got umask)" in
    0077|077|77) printf 'PASS  the umask is private to the child\n' ;;
    *) fail "umask was not tightened: $(got umask)" ;;
  esac

  # Resource ceilings must actually be finite, or nothing is bounded at all.
  bounded=1
  for limit in ulimit_cpu ulimit_procs ulimit_open ulimit_file; do
    value="$(got "$limit")"
    if [[ "$value" == unlimited ]]; then
      fail "$limit is unlimited, so a runaway process is not bounded"
      bounded=0
    fi
  done
  (( bounded )) && printf 'PASS  every resource ceiling is finite\n'

  # A non-interactive invocation must be refused, so the wrapper cannot be used as
  # an automation path that looks like an interactive session.
  if run_as "$probe_user" bash "$(realpath "$SHELL_SRC")" </dev/null \
       >"$probe_dir/noninteractive.log" 2>&1; then
    fail 'the wrapper ran non-interactively'
  else
    printf 'PASS  the wrapper refuses to run without a terminal\n'
  fi

  # The wrapper must refuse an account it was not written for.
  printf 'somebody-else\n' >"$account_file"
  if run_as "$probe_user" bash "$(realpath "$SHELL_SRC")" </dev/null \
       >/dev/null 2>&1; then
    fail 'the wrapper ran for an account it was not written for'
  else
    printf 'PASS  the wrapper refuses an account it was not written for\n'
  fi
  printf '%s\n' "$probe_user" >"$account_file"

  # A missing or malformed account file must refuse, not fall back to a default
  # the child could satisfy.
  : >"$account_file"
  if run_as "$probe_user" bash "$(realpath "$SHELL_SRC")" </dev/null >/dev/null 2>&1; then
    fail 'the wrapper ran with no account file'
  else
    printf 'PASS  the wrapper refuses when the account file is empty\n'
  fi
  printf 'not a valid name!\n' >"$account_file"
  if run_as "$probe_user" bash "$(realpath "$SHELL_SRC")" </dev/null >/dev/null 2>&1; then
    fail 'the wrapper ran with a malformed account name'
  else
    printf 'PASS  the wrapper refuses a malformed account name\n'
  fi
  printf '%s\n' "$probe_user" >"$account_file"
else
  printf 'note  no unprivileged account is available here, so the wrapper'"'"'s limits are not exercised\n'
  printf '      (it refuses this account, correctly); run tests/fedora-container for full coverage\n'
fi

rm -f "$probe_dir/out"
printf 'somebody-else\n' >"$account_file"
if CHILD_UNDER_TEST=somebody-else bash "$SHELL_SRC" </dev/null >/dev/null 2>&1; then
  fail 'the wrapper ran for a different child account name'
else
  printf 'PASS  the wrapper refuses when the child account name does not match\n'
fi

# The honest part: state plainly what the limits do not stop, and assert that the
# documentation does not claim otherwise.
if grep -q 'speed bump, not a security boundary' "$SHELL_SRC"; then
  printf 'PASS  the wrapper states that it is not a security boundary\n'
else
  fail 'the wrapper does not state its own limits'
fi
if grep -qE 'types /bin/bash' "$SHELL_SRC"; then
  printf 'PASS  the wrapper states that /bin/bash defeats it\n'
else
  fail 'the wrapper does not admit that a shell escape is trivial'
fi

# The administrator refusal is not exercised above, because the only account
# available here is not in wheel or sudo, and testing it would mean creating an
# administrator account. Assert the branch is present instead of pretending the
# behaviour was observed, and say so.
if grep -q "grep -Eq '^(wheel|sudo)\$'" "$SHELL_SRC"; then
  printf 'PASS  the wrapper refuses administrator accounts (branch present, not exercised here)\n'
else
  fail 'the wrapper has no administrator-account refusal'
fi

if (( failures > 0 )); then
  printf '\nchild-shell tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'Child shell wrapper tests passed.\n'
