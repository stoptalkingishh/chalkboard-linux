# Architecture

## Shared policy, platform-specific enforcement

The repository separates intent from implementation:

1. Shared policy defines account roles, allowed capabilities, recovery paths,
   network guardrails, and age-appropriate applications.
2. Platform adapters implement only the controls the operating system supports.
3. Verification checks effective behavior instead of assuming a configuration
   file was honored.

Fedora can be configured with shell scripts and system policy. Apple Family
Sharing is configured through Apple's supported account and Screen Time flows.
Fire OS combines supported settings with narrowly scoped, optional ADB actions.
These are intentionally different implementations.

## Linux rollout phases

1. Audit the OS, desktop, display manager, network stack, and hardware.
2. Create or verify separate parent and child accounts.
3. Install a reviewed application catalog.
4. Apply network filtering and verify browser DNS behavior.
5. Configure power and input settings per hardware profile.
6. Build the child Plasma layout through supported Plasma mechanisms.
7. Apply restrictions only after parent recovery has been tested.
8. Run behavioral verification and record a local change manifest.

Mutating commands are idempotent and rerunnable, and preserve the first
pre-existing value of each managed file in a root-owned local state directory.
`install_managed_file` in `scripts/fedora/lib.sh` calls `backup_file` before
installing, and `backup_file` returns immediately if a backup already exists.
Only the first value is preserved: a later rerun that changes a managed file
does not update the saved original. Re-running a completed phase must not
duplicate repositories, launchers, widgets, or configuration.

Dry runs are the exception, not the rule. Only
`scripts/fedora/create-child-user.sh` implements `--dry-run`. Other commands
apply changes directly, so review the audit and the phase's documentation
before running them. `scripts/fedora/weather.sh` rewrites
`/etc/chalkboard/weather.conf` on every enable or disable without backing up
each intermediate change, so the saved original is the pre-deployment file,
not the previous weather setting.

## Boundaries

### DNS filtering

Cloudflare Family DNS is the default. A parent may instead provide a deployment-
specific NextDNS configuration ID after reviewing that service's policy and
logging options. Resolver backends are alternatives, never combined. Neither
can block every unsuitable page, search result, application, VPN, hard-coded IP
address, or browser using its own encrypted DNS provider. The Fedora adapter
must account for NetworkManager and browser DNS settings and must verify the
effective resolver after configuration.

### Simplified desktop

Directly rewriting `plasma-org.kde.plasma.desktop-appletsrc` is fragile and can
corrupt or duplicate panels across Plasma versions. Prefer Plasma scripting,
targeted immutable KDE settings where appropriate, and a dedicated child account.
Never restrict the parent account with child policy.

The child session remains a normal multitasking desktop. Policy fixes the panel
layout and hides advanced launch paths; it does not block ordinary application
behavior or replace Linux account permissions.

Convertible devices use Plasma Desktop's packaged automatic tablet mode,
Plasma Keyboard, KScreen, and `iio-sensor-proxy`. Plasma Mobile is not used
because it is a separate phone-oriented session rather than an adaptive laptop
mode, and traditional desktop applications remain part of this project.

The optional GCompris mode is a separate SDDM Wayland session using Fedora's
packaged Cage kiosk compositor. Cage launches GCompris as its sole client, so
Plasma, its launchers, and its window-management shortcuts are not present. This
reduces ordinary accidental escape paths but remains an interface restriction,
not a security boundary. The unprivileged account and Linux permissions remain
the security boundary.

Instead of a full system tray, the child panel explicitly provides running
windows, removable devices, notifications, Bluetooth, volume, Wi-Fi, battery,
and confirmed power actions. A documented parent recovery path remains required.

### Power behavior

Suspend support and lid behavior are hardware-specific, so neither belongs in a
generic default. The Fedora adapter is an explicit, device-confirmed exception:
`deploy.sh` installs the logind and sleep drop-ins and masks the sleep targets
for this one hardware profile, which disables suspend for every account on the
machine, including the parent's, and is restored only by full rollback. Any new
platform adapter must make the same trade-off explicit rather than inheriting
it.

### Web applications

A browser `--app=URL` launcher changes presentation; it is not a sandbox or a
kiosk. External navigation, downloads, browser policy, and account behavior
must be tested separately. Only official, currently available URLs should be
included in the catalog.

### Parent-owned retro software

Optional Windows games use one Wine prefix per registration. A root-only parent
workflow verifies parent-supplied installer bytes, runs setup without elevated
privileges, and publishes a fixed child launcher only after the configured
executable is present inside that prefix. Root-owned metadata contains paths,
not shell commands. Wine prefixes are separation for manageability, not security
sandboxes; the game still has the child account's file, device, and network
access. No game media or title-specific circumvention/configuration belongs in
this repository.

## Repository layout

```text
config/fedora/            managed configuration data, the source of truth
  app-allowlist.txt       Dashboard curation allowlist
  kde/panel.js            child panel layout, applied by first-login
  kde/weather.js          optional weather widget reconciliation
  launchers/*.desktop     child launcher definitions
  systemd/                screen-time service and timer units
  systemd-resolved.conf           Cloudflare drop-in
  systemd-resolved-nextdns.conf   NextDNS drop-in
  vivaldi-policy.json     managed Vivaldi policy
  vivaldi.repo            signed upstream RPM repository
docs/                     policy, runbooks, and boundaries
scripts/fedora/           implementation
tests/                    static and behavioral checks
```

`config/fedora/` is the single source of truth for the data installed onto the
device; the scripts only install, never restate. It is reviewed without
executing code, and the remaining managed files (SDDM, logind, sleep, KDE
policy, PowerDevil, screen-time, and the GCompris session) sit beside the
examples above.
