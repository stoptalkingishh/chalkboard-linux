# Fedora screen time

Chalkboard provides optional, parent-managed recurring downtime for the
dedicated child account. Installation does not enable enforcement, and the
shipped schedule has no downtime windows.

## Install and configure

Install the framework on Fedora 43:

```bash
sudo bash scripts/fedora/install-screen-time.sh
```

As a parent, edit `/etc/chalkboard/screen-time.conf`. It is root-owned mode
`0600`, is rejected if writable by a non-root user, and is not exposed through
the child desktop. Windows use `HH:MM-HH:MM`, are start-inclusive and
end-exclusive, may cross midnight, and may be comma-separated. For example,
`friday = 21:30-07:00` starts Friday and ends Saturday. Equal start and end
times are rejected rather than interpreted as all day.

The configured user must be an unprivileged account with UID 1000 or greater;
administrator and system accounts are refused. Release active downtime before
changing the configured user.

`timezone = local` evaluates wall-clock weekdays and times in the system
timezone and follows parent changes made with `timedatectl`. Set an IANA zone
such as `America/New_York` to keep the schedule tied to that zone while the
system timezone changes. During daylight-saving transitions, the configured
wall-clock labels apply: a repeated time is downtime in both occurrences, while
a window that falls entirely inside a skipped hour is not active on that clock
jump day. Windows that extend past the skipped boundary apply at the first
timer check after the time change.
The timer also runs after clock and timezone changes.

Validate and opt in explicitly:

```bash
sudo chalkboard-screen-time check
sudo chalkboard-screen-time enable
sudo chalkboard-screen-time status
```

## Behavior and boundary

The root systemd timer checks every 30 seconds. Before downtime it attempts a
desktop notification. At the boundary it records the account's existing expiry,
sets the child account expiry to a past date using `chage`, attempts another
notification, waits the configured grace period, and asks systemd-logind to
terminate every child session. PAM account checks then prevent ordinary SDDM,
console, and SSH logins until release. The password-locked child account and
SDDM autologin are covered by Fedora's PAM account stack. Session termination
is retried on each check during downtime, including after an interrupted run.

Notifications are best effort: there may be no graphical session or notification
service. Enforcement still proceeds. Unsaved application work can be lost when
the grace period ends. The check interval means a boundary can be applied up to
about 31 seconds late, and up to about 15 seconds after boot when enabled.

This feature controls the configured child account, not parent/root sessions.
It does not power off the computer, filter network traffic, count active minutes,
or implement per-application daily limits. Fedora 43 packages malcontent, but
its app filter does not provide reliable daily runtime accounting across KDE,
direct executable launches, browsers, and Flatpak, so Chalkboard does not claim
or configure that capability.

## Disable and recover

Disable enforcement and restore the exact account expiry saved when downtime
started:

```bash
sudo chalkboard-screen-time disable
```

If another administrator changed the account expiry during active downtime,
normal disable stops and refuses to overwrite that change. Inspect
`/var/lib/chalkboard/screen-time/state.json`, then deliberately restore the
saved value with:

```bash
sudo chalkboard-screen-time force-disable
```

These commands work over SSH or a local text console as the parent. If systemd
is unavailable, run `/usr/local/libexec/chalkboard-screen-time force-release`
as root, then disable the timer. Release uses protected runtime state and still
works if the schedule config is malformed or missing. Repository-wide
`rollback.sh` also force-releases downtime before restoring installed files.
