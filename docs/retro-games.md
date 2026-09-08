# Optional retro-game framework

This Fedora 43 workflow lets a parent install a lawfully owned Windows game into
an isolated Wine prefix and publish one fixed launcher to the `chalkboard`
account. It is optional and is not run by `deploy.sh`. Chalkboard distributes no
games, artwork, keys, cracks, patches, DRM bypasses, CD-check bypasses, or
title-specific configuration.

No title is claimed compatible. The parent must test installation, launch,
input, audio, display recovery, saving, networking, and uninstall behavior on
the actual device before making a launcher available to a child.

## Runner choice

Fedora's package index lists both Wine 10 and Lutris 0.5.19 builds for Fedora
43. Package presence is dependable enough to install from Fedora's signed
`fedora` and `updates` repositories. This framework deliberately uses Wine
directly and does not install Lutris. Lutris exposes a general game manager,
online service integrations, community installer scripts, and separately
downloaded runners that are outside this minimal curated-launcher model.

Repository availability does not establish game compatibility. Fedora 43 uses
Wine's newer WoW64 mode, and old installers, copy protection, graphics APIs, and
hardware can still fail. Do not work around DRM or media checks; use a lawful,
publisher-supported installer or do not register the title.

## Before installation

1. Complete the main Fedora deployment and confirm parent recovery access.
2. Log into the child graphical session and remain present throughout setup.
3. Back up the device and any existing game saves.
4. Obtain the installer directly from owned physical media or an authenticated
   publisher/store account. Do not use repacks or third-party cracks.
5. Calculate and record the exact local file's digest with
   `sha256sum /absolute/path/to/installer.exe`. A digest detects accidental or
   later substitution; it does not prove that an untrusted file is safe.
6. Determine the installed executable's path relative to the Wine prefix. It
   must begin with `drive_c/` and end with `.exe`.

## Install and register

From the repository checkout, run the following over the parent's SSH or text
console while the child graphical session is active:

```bash
sudo bash scripts/fedora/retro-game.sh install \
  --id my-game \
  --name "My Game" \
  --installer /absolute/path/to/installer.exe \
  --sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  --executable "drive_c/Program Files/My Game/game.exe" \
  --owned-media
```

Replace every example value. `--owned-media` is an explicit parent attestation,
not a license determination. The script verifies the digest, installs Wine only
from Fedora's enabled official repositories, runs the installer as the
unprivileged child user, and checks that the selected executable resolves inside
the new prefix. It masks Fedora's generic Wine utility launchers for the child,
disables Wine's automatic menu builder, and writes the game launcher only after
setup succeeds.

Re-running the same command verifies the existing registration and does not run
the installer again. To replace an installation, uninstall it and then install
it again. IDs accept only lowercase ASCII letters, digits, and hyphens; names and
executable paths use a restricted grammar. No shell command, Wine argument, URL,
environment override, or arbitrary launcher argument can be registered.

Registrations are root-owned under `/usr/local/share/chalkboard/retro-games`.
Game files and saves are under:

```text
/home/chalkboard/.local/share/chalkboard/retro/ID/prefix
```

The supplied installer is removed after setup and is never committed or copied
into the repository.

## Verify

Run structural verification as the parent:

```bash
sudo bash scripts/fedora/retro-game.sh verify my-game
```

Then test graphically from the child launcher. Structural verification confirms
the fixed command, ownership-independent path containment, executable presence,
and Wine RPM. It cannot prove compatibility, safety, licensing, or correct game
behavior.

## Uninstall and restore

Close Wine processes for the game, then run:

```bash
sudo bash scripts/fedora/retro-game.sh uninstall my-game
```

This removes the launcher, registration, prefix, and saves after copying them to
a timestamped root-only directory under `/var/lib/chalkboard/retro/backups`.
Inspect available disk space first: a backup can be as large as the installed
game. To restore, reinstall from the original lawful installer, test it, stop
Wine, and copy only required save data from the backup. Restoring a complete old
prefix can reintroduce vulnerable or broken binaries, so it is intentionally not
automatic. Delete backups manually only after confirming they are no longer
needed and local licensing permits retention.

The main `rollback.sh` restores or removes the framework wrapper and configured
username because those files use Chalkboard's normal first-write backup. It does
not delete game prefixes, registrations, or local copyrighted backups. Uninstall
each game first if complete removal is desired. The Wine RPM is retained to
avoid removing packages another application may use.

## Security boundaries

- Wine is a compatibility layer, not a sandbox. A Windows installer or game runs
  with the child's Linux permissions and may read or alter child-owned files,
  access devices exposed to the session, and use the network.
- Separate prefixes reduce accidental cross-game changes but do not isolate
  processes from the child account or the network.
- Parent supervision, a matching digest, antivirus checks, and a reputable
  source reduce risk but cannot make untrusted executables safe.
- The fixed wrapper accepts exactly one validated ID, reads root-owned metadata,
  rejects path traversal and symlink escape, and supplies no free-form command
  or arguments. This prevents launcher-command injection; it does not prevent a
  child from running other software available through the normal desktop.
- Online games, telemetry, chat, purchases, advertising, and account systems
  need separate parental review. Family DNS is not a complete content boundary.
- Old software may contain known vulnerabilities or require unsafe obsolete
  components. Do not weaken SELinux, firewall, account permissions, or system
  libraries to make a game run.
