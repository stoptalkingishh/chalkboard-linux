#!/usr/bin/env bash

# Interactive shell for the child account.
#
# This is a speed bump, not a security boundary, and the distinction matters.
# The boundary is the unprivileged account itself: it is not in wheel or sudo, its
# password is locked, and on Fedora 43 no polkit action grants an active
# unprivileged session user anything that runs as root. A child who reaches this
# shell has gained nothing they did not already have.
#
# What this does buy, which is the point of deploying it:
#
#   * resource ceilings, so a runaway process cannot fill the disk, exhaust
#     memory or processes, or wedge the device the parent needs to recover it
#   * the environment variables that let a program be made to do something
#     else, cleared
#   * no shell history file in the child's home to read, or to poison
#   * no grouping or path surprises
#
# What it does NOT buy, and should not be advertised as:
#
#   * any protection against a child who types /bin/bash. Nothing in this
#     wrapper survives that, and pretending otherwise would be worse than not
#     having it.
#   * a restriction on which commands run. python3, perl, awk, find -exec, xargs
#     and env are all present and all run at the child's own privilege, which is
#     the same privilege they already had.
#
# The genuinely locked-down fallback is the optional GCompris Cage session, which
# gives a child one application and no shell at all. This wrapper is the
# graduated response between the normal desktop and that mode.

set -u

# The account this wrapper is for, recorded next to the wrapper by deploy.sh.
# It is read from a root-owned file rather than the environment, because the
# environment belongs to whoever invoked the shell. Reading a name from the
# environment would mean a child could point the wrapper at a different account,
# and it is the same mistake as making the limits below environment-controlled.
ACCOUNT_FILE="${CHALKBOARD_CHILD_ACCOUNT_FILE:-/usr/local/bin/.chalkboard-child-user}"
[[ -r "$ACCOUNT_FILE" ]] || {
  printf 'chalkboard-child-shell: no child account file at %s\n' "$ACCOUNT_FILE" >&2
  exit 1
}
expected_user="$(<"$ACCOUNT_FILE")"
expected_user="${expected_user//[$'\t\r\n ']/}"
[[ "$expected_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
  printf 'chalkboard-child-shell: %s does not contain a usable account name\n' \
    "$ACCOUNT_FILE" >&2
  exit 1
}

# Only the child account may use this. An account that is a member of wheel or
# sudo, or that is a system account, is refused outright rather than run with
# limits, so the wrapper can never be mistaken for a hardening measure for an
# administrator's account. The account name comes from id(1), not from $USER,
# which the caller controls.
self_user="$(id -un)"
if [[ "$self_user" != "$expected_user" ]]; then
  printf 'chalkboard-child-shell: refusing to run for account %s\n' "$self_user" >&2
  exit 1
fi
if [[ "$(id -u)" -lt 1000 ]]; then
  printf 'chalkboard-child-shell: refusing to run for a system account\n' >&2
  exit 1
fi
if id -nG "$self_user" 2>/dev/null | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'; then
  printf 'chalkboard-child-shell: refusing to run for an administrator account\n' >&2
  exit 1
fi

# A non-interactive invocation is a program trying to run a command, not a child
# sitting at a prompt. Refuse it, so this wrapper cannot be used to launder an
# automation path into something that looks like an interactive session.
if [[ ! -t 0 && ! -t 1 ]]; then
  printf 'chalkboard-child-shell: refusing to run without a terminal; use a normal program launcher instead\n' >&2
  exit 1
fi

umask 077

# Resource ceilings, deliberately not configurable. An earlier version read these
# from CHALKBOARD_ULIMIT_* environment variables, which the child controls and
# could therefore set to "unlimited" before re-entering this shell.
#
# The values are generous enough that a child browsing, writing a document or
# drawing a picture will not reach them, and bounded enough that a runaway loop
# cannot wedge the device the parent needs in order to recover it.
ulimit -t 120 2>/dev/null || \
  printf 'chalkboard-child-shell: could not set the CPU limit\n' >&2
ulimit -u 200 2>/dev/null || \
  printf 'chalkboard-child-shell: could not set the process limit\n' >&2
ulimit -n 512 2>/dev/null || \
  printf 'chalkboard-child-shell: could not set the open-file limit\n' >&2
# 524288 blocks of 512 bytes is 256 MiB.
ulimit -f 524288 2>/dev/null || \
  printf 'chalkboard-child-shell: could not set the file size limit\n' >&2

# Environment variables that redirect a program's behaviour. A child cannot set
# them through this wrapper's environment, but a launched application can, and
# the ones below are the ones that change what a program does rather than how it
# is found.
unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT LD_DEBUG
unset BASH_ENV ENV CDPATH GLOBIGNORE
unset PYTHONPATH PYTHONHOME PYTHONSTARTUP
unset PERL5LIB PERLLIB RUBYLIB RUBYOPT
unset MALLOC_TRACE GLIBC_TUNABLES
unset IFS

export PATH=/usr/bin:/bin
export HISTFILE=/dev/null
export HISTSIZE=0
export HISTCONTROL=
export LESSHISTFILE=-
# Makes the restriction visible to a program that wants to know, without
# pretending to be enforcement.
export CHALKBOARD_RESTRICTED_SHELL=1

# Clear the inherited signal dispositions and job control of whatever launched
# the terminal, so a Ctrl-C from the desktop session is not ignored and a trapped
# SIGINT is not inherited as ignored.
trap - INT QUIT TERM 2>/dev/null || true

exec /bin/bash --noprofile --norc -i
