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

Each mutating command must support a dry run where practical and preserve the
previous value in a root-owned local state directory. Re-running a completed
phase must not duplicate repositories, launchers, widgets, or configuration.

## Boundaries

### DNS filtering

Cloudflare Family DNS can reduce accidental exposure to known malware and adult
domains. It does not block every unsuitable page, search result, application,
VPN, hard-coded IP address, or browser using its own encrypted DNS provider.
The Fedora adapter must account for NetworkManager and browser DNS settings and
must verify the effective resolver after configuration.

### Simplified desktop

Directly rewriting `plasma-org.kde.plasma.desktop-appletsrc` is fragile and can
corrupt or duplicate panels across Plasma versions. Prefer Plasma scripting,
targeted immutable KDE settings where appropriate, and a dedicated child account.
Never restrict the parent account with child policy.

The child session remains a normal multitasking desktop. Policy fixes the panel
layout and hides advanced launch paths; it does not block ordinary application
behavior or replace Linux account permissions.

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

Suspend support and lid behavior are hardware-specific. The project must not
disable suspend or convert lid-close to shutdown on every device by default.
Those changes belong in an explicit hardware profile and require confirmation.

### Web applications

A browser `--app=URL` launcher changes presentation; it is not a sandbox or a
kiosk. External navigation, downloads, browser policy, and account behavior
must be tested separately. Only official, currently available URLs should be
included in the catalog.

## Repository layout

```text
docs/
  architecture.md
  platforms/
scripts/
  fedora/
```

Future configuration data should remain separate from shell implementation so
application catalogs and policy defaults can be reviewed without executing
code.
