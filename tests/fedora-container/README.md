# Fedora 43 container integration tests

These run the shipped curation and verification scripts inside a real Fedora 43
root filesystem, against the desktop file database that Fedora's own packages
produce, and against a real unprivileged `chalkboard` account.

## Why this exists

`tests/app-menu.sh` uses fixtures, and fixtures can lie. Two bugs in the verifier
shipped through the fixture-based tests and were caught only here:

**1. The applet lookup was in the wrong order.** Plasma writes the applet header,
then `plugin=`, and only then the applet's `[Configuration][General]` group:

```
[Containments][75][Applets][76]
plugin=org.kde.plasma.kickerdash
                                   <- blank
[Containments][75][Applets][76][Configuration][General]
favoriteApps=...
hiddenApplications=...
```

The verifier looked for the group header *before* the plugin line, so it never
found the key and always reported "no hiddenApplications key". The fixture
happened to be written in the same wrong order, so the fixture and the bug agreed
with each other and disagreed with every real device.

**2. The verifier and the curation writer had different definitions of
"visible".** `curate-app-menu.sh` skips entries with `NoDisplay=true` or
`Hidden=true`, because most KDE control-centre modules are NoDisplay: reachable
from the settings UI, not from the application menu. The verifier enumerated
filenames instead of parsing entries, so it expected 150-odd `kcm_*.desktop`
modules in a denylist that curation correctly never writes. A count threshold
would have hidden this too.

Both bugs are now prevented structurally: the visibility enumeration, allowlist
parsing, and applet lookup live in `scripts/fedora/lib.sh` and are called by both
the writer and the verifier, so they cannot drift apart.

## What this does and does not establish

**Does establish:**

- The curation and verification scripts run on a real Fedora 43 userspace with
  the real `bash` 5.3, `gawk`, `kwriteconfig6`, and ~150 real KDE desktop files.
- Curation and verification agree on the real desktop file database.
- The apps the project exists to hide (Konsole, System Settings) are hidden; the
  allowlisted apps are not.
- The verifier rejects a denylist that re-exposes Konsole, hides an allowlisted
  app, names an application that is not installed, or includes a NoDisplay entry.
- The verifier fails closed when the applet config is absent.
- Curation is idempotent.
- `lib.sh`'s applet lookup uses no GNU awk extension, so the scripts no longer
  depend on `gawk` being installed (this was previously the one thing in the repo
  that could not run on a stock Debian or Ubuntu CI image).

**Does not establish — needs the real device:**

- Anything graphical: Plasma Shell, the panel, the Application Dashboard, SDDM
  autologin, KWin, touch input, the virtual keyboard, tablet-mode switching.
- Whether the kiosk policy in `config/fedora/kde/kdeglobals` is actually
  enforced, including whether `plasma-desktop/scripting_console=false` blocks
  `org.kde.PlasmaShell.evaluateScript` over D-Bus. There is no display server,
  no D-Bus, and no Plasma here.
- Whether `~/.config/kdeglobals` shadows the policy in `/etc/xdg/chalkboard`.
- The `install -d` and `install` symlink behaviours, which are coreutils, not
  Fedora packages, and are already covered by `tests/rollback.sh`.
- DNS filtering, DoT, and the NetworkManager dispatcher.
- Screen-time enforcement, which needs a real account expiry and a real session
  to terminate.
- Hardware power, lid, and sensor behaviour.

## Running it

```bash
docker build -t chalkboard-f43:test -f tests/fedora-container/Dockerfile .

docker run --rm --user root \
  -v "$PWD:/repo:ro" -w /repo \
  chalkboard-f43:test bash tests/fedora-container/run.sh
```

The first build downloads and installs the KDE package set and takes several
minutes. Later runs reuse the image and take seconds.

## The full provisioning pipeline

`tests/fedora-container/pipeline.sh` exercises `deploy.sh`,
`finalize-lockdown.sh`, `verify.sh`, and `rollback.sh` end to end. It needs
systemd as PID 1, so run it as a detached container and then `exec`:

```bash
docker rm -f cb-sysd
docker run -d --name cb-sysd --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$PWD:/repo:ro" \
  --entrypoint /usr/lib/systemd/systemd \
  chalkboard-f43:test /libexec/systemd/systemd-multi-user.target
sleep 15
docker cp tests/fedora-container/pipeline.sh cb-sysd:/pipeline.sh
docker exec cb-sysd bash /pipeline.sh
docker rm -f cb-sysd
```

That takes several minutes on the first run because `deploy.sh` installs
Vivaldi from its upstream repository and CuteMaze from Flathub.

**Expected result:** one failure, `rotation sensor service is active`.
`iio-sensor-proxy` is installed but has no IIO device to attach to, because a
container has no sensors. That check passes on the laptop.

This pipeline found two defects that nothing else could have found, both in code
that had already passed every other test layer:

1. `apply-family-dns.sh` set both address families in a single `nmcli modify`.
   NetworkManager rejects `ipv6.dns` on a connection whose `ipv6.method` is
   `disabled`, and applies a modify atomically, so the rejection discarded the
   IPv4 filtering too. The dispatcher runs on every activation and NetworkManager
   ignores its exit status, so that connection silently kept an **unfiltered
   resolver** — and `deploy.sh` aborted before installing anything else.
2. `check-app-menu.sh` sourced `"$SCRIPT_DIR/lib.sh"`, but it is installed as
   `/usr/local/libexec/chalkboard-check-app-menu`, where `lib.sh` is installed
   under the name `chalkboard-lib`. The installed copy could not find it, so
   `finalize-lockdown.sh` aborted before writing the finalized marker and
   `verify.sh` reported two failures on a freshly deployed device. The
   fixture-based tests could not catch it because they run the scripts from the
   repository, where `lib.sh` is a neighbour.

Neither is reachable from a desktop environment that already has a repository
checkout and an IPv6-enabled Wi-Fi profile, which is why both survived to
production-shaped code.

The Dockerfile is not wired into `tests/static.sh` or CI, because a multi-minute
image build does not belong in a pull-request gate. Run it deliberately when
changing `deploy.sh`, `finalize-lockdown.sh`, `verify.sh`, `rollback.sh`,
`apply-family-dns.sh`, `curate-app-menu.sh`, `check-app-menu.sh`, or `lib.sh`.

## Deploying to an image

`tests/fedora-container/deploy.sh` is the same pipeline without the rollback, so
the container is left in a deployed state and can be committed into an image:

```bash
docker rm -f cb-deployed
docker run -d --name cb-deployed --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$PWD:/repo:ro" \
  --entrypoint /usr/lib/systemd/systemd \
  chalkboard-f43:test /libexec/systemd/systemd-multi-user.target
sleep 15
docker cp tests/fedora-container/deploy.sh cb-deployed:/deploy.sh
docker exec cb-deployed bash /deploy.sh

docker commit -m "Chalkboard deployed" cb-deployed chalkboard-f43:deployed
```

The result verifies at 35 passes and one expected failure
(`rotation sensor service is active`, because a container has no IIO device).
Every file the deployment installs is byte-identical to the repository, which is
worth asserting: it is what caught the installed-helper bug, where the installed
copy of a script could not find `lib.sh` under its renamed name.
