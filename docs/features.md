# Fedora feature set

## Accounts and login

- Creates or verifies a dedicated `chalkboard` account.
- Keeps the child account out of `wheel` and `sudo`.
- Locks password authentication for the child account.
- Configures SDDM to autologin to the Plasma Wayland session after boot.
- Leaves the parent account and its Plasma configuration unchanged, but not
  the system-wide power policy; see the Power section.
- Disables automatic screen locking because a password-locked autologin account
  could not unlock itself.
- Disables KDE Wallet and Vivaldi password saving to avoid wallet prompts or
  secret-service failures in a passwordless autologin session.

## Desktop

- Uses Plasma Desktop's built-in automatic tablet mode rather than a custom
  shell or custom QML.
- Uses KDE's full-screen Application Dashboard and an Icons-only Task Manager.
  The Dashboard lists every approved application as a favorite for labeled
  discovery, while the compact task-panel launchers keep a small set of primary
  shortcuts. Normal running-window switching remains.
- Keeps ordinary Dashboard application browsing, but removes recent documents
  and extra search runners from the child-facing menu.
- Curates the Application Dashboard to an explicit allowlist: every installed
  application that is not in `config/fedora/app-allowlist.txt` is hidden. This
  removes Fedora/KDE system tools, the software center, email/chat clients, and
  development utilities while keeping the curated applications, the browser, and
  Dolphin. `deploy.sh` does not install `dolphin`; the allowlist entry for
  `org.kde.dolphin.desktop` relies on Dolphin already being present on the
  Fedora KDE image, and `Super+E` opens it only if it is installed.
- Uses a 68-pixel panel and 175% scaling on the high-density internal display.
- Enables Plasma Keyboard for touch text entry and `iio-sensor-proxy` for
  supported automatic rotation.
- Removes the traditional application menu and full system tray.
- Adds standalone removable-device, notification, Bluetooth, volume, Wi-Fi, and
  battery widgets without restoring the full system tray.
- Adds a touch-friendly power menu that requires confirmation before shutdown or
  restart.
 - Disables KRunner, terminal, and application-launcher shortcuts in the child
   session while preserving `Super+E` for Dolphin file management.
 - Sets the child account's login shell to a restricted wrapper
   (`/usr/local/bin/chalkboard-child-shell`) as a second line of defence, for the
   case where a terminal is reached some other way. See
   [Restricted child shell](#restricted-child-shell) below for what it does and,
   more importantly, what it does not do.
- Disables panel editing and desktop scripting through immutable KDE policy.
  The policy is installed at finalization and applies to the child session only;
  the parent is not restricted by `/etc/xdg/chalkboard`. Whether
  `plasma-desktop/scripting_console=false` also blocks
  `org.kde.PlasmaShell.evaluateScript` over D-Bus is not covered by any
  automated test and requires graphical verification.
- Preserves normal application behavior, file dialogs, multitasking, and window
  management.
- Attempts to disable tap-to-click for each touchpad exposed by KWin during the
  first child session. Detachable hardware may expose no touchpad while its
  keyboard cover is disconnected.
- Optionally adds Fedora's packaged KDE weather widget only after a parent
  explicitly selects the NOAA provider and a station. The widget is disabled by
  default, does not alter baseline panel provisioning, and is removed cleanly
  when disabled.
- Refuses weather changes once `/var/lib/chalkboard/finalized` exists, because
  `finalize-lockdown.sh` creates that marker. This is a marker-file check in
  `scripts/fedora/weather.sh`, not a consequence of the locked shell; see the
  recovery guide.

KDE policy keeps the simplified layout consistent; it is not a security sandbox.
The separate non-admin account is the primary privilege boundary.

## Restricted child shell

The child account's login shell is `/usr/local/bin/chalkboard-child-shell`. It
exists because the primary control, hiding Konsole, is an appearance setting
that a determined child can undo from an application menu, a `.desktop` file, or
a file manager. The wrapper is the fallback for a terminal that appears anyway.

It starts an interactive `bash` for the child account with:

- the account name read from the root-owned `/usr/local/bin/.chalkboard-child-user`
  rather than from the environment, since the environment belongs to whoever
  invokes the shell;
- a refusal to run unless the caller is that account, is a real login account
  (UID ≥ 1000), is not in `wheel` or `sudo`, and has a terminal;
- `PATH` pinned to `/usr/bin:/bin` and interpreter variables such as
  `PYTHONPATH`, `PERL5LIB`, `BASH_ENV` and `LD_PRELOAD` cleared;
- no history file and `umask 077`, so nothing the child runs is world-readable;
- fixed ceilings: 120 s CPU, 200 processes, 512 open files, 512 KiB per file.
  These bound a runaway process; they are not a quota system.

### What it does not do

This is a speed bump, not a security boundary, and the boundary has not moved:

- The child can run `/bin/bash`, `python3`, `perl`, `awk`, or `find -exec` and get
  an unrestricted shell or interpreter at their existing unprivileged UID.
- The resource limits are per-process and inherited, so a child can work around
  them by running fewer processes.
- The wrapper protects the *terminal*, not the account. Anything else the child
  can reach, including Dolphin, still gives file and `.desktop` access.

What the wrapper actually protects against is the accidental case: a child who
reaches a terminal and starts typing discovers there is no history file, a
private umask, and finite resource limits. The account itself remains the real
boundary: unprivileged, password-locked, and outside `wheel` and `sudo`.

`tests/child-shell.sh` drives the wrapper through a pty as the real child
account and asserts each behaviour above. Each assertion was checked against a
deliberately broken copy of the wrapper to confirm the test fails when the
behaviour is removed, rather than passing because it observed nothing. The
administrator-account refusal is asserted by source inspection only, because
exercising it would require creating an administrator account.

## Optional single-app mode

- Installs Fedora's Cage Wayland kiosk compositor and a dedicated SDDM session,
  but leaves the normal child Plasma session selected by default.
- Requires an explicit root command to enable or disable the mode.
- Runs GCompris fullscreen with its own kiosk option as Cage's only client.
- Provides no Plasma shell, panel, launcher, task switcher, or desktop shortcuts.
- Allows VT switching so a parent can recover from a local text console.
- Does not automatically relaunch a failed or exited session; SDDM displays its
  greeter instead, avoiding a crash/relogin loop.
- Returns to GCompris after a normal power cycle while enabled and returns to
  Plasma after the parent disables it and reboots.

This mode does not sandbox GCompris, harden the kernel, block physical boot-media
access, or protect data that the `chalkboard` Unix account can already access.
GCompris activities, file dialogs, accessibility behavior, and future upstream
changes require graphical testing.

## Applications

Native Fedora packages:

- GCompris
- KolourPaint
- KCalc
- LibreOffice Writer
- Ktuberling
- KMines

Additional software:

- Vivaldi from its signed official RPM repository
- CuteMaze from the system-wide verified Flathub repository
- Kid Pix as a Vivaldi app window
- Teach Your Monster as a direct-play Vivaldi app window after parent setup
- Coolmath Games as a Vivaldi app window
- A general Vivaldi browser launcher

Vivaldi receives mandatory policy that disables browser DNS-over-HTTPS, guest
mode, additional browser profiles, incognito mode, and developer tools, and sets
`ExtensionInstallBlocklist` to `*`, which blocks installation of extensions. It
does not remove extensions that are already installed, so a parent must also
confirm the child profile has none. Google SafeSearch and YouTube Restricted
Mode are requested through Chromium policy, and browser password saving is
disabled. Effective policy must be confirmed at `vivaldi://policy` during
graphical testing.

Kid Pix, Teach Your Monster, and Coolmath Games are each a
`vivaldi-stable --app=URL` window: a full browser window that the child can
navigate away from, open new tabs in, and use the address bar in. It is a
presentation choice, not a sandbox. `chalkboard-browser.desktop` is a plain
browser launcher with no URL restriction, so the child can reach any site that
passes DNS filtering and browser policy. See the architecture boundaries for
what this does and does not prevent.

Vivaldi does not provide a verified policy or command-line switch that skips its
own welcome flow. A parent must complete it once before lockdown. Teach Your
Monster also requires a free parent account, email confirmation, and player
creation before its direct-play launcher can work.

CoolmathGames.com states that it is designed for ages 13 and older. Its free
service uses interest-based advertising and collects browser, device, and usage
information. It is included by explicit project-owner choice and should be
removed for a child who does not meet that age requirement.

## Network

- Replaces DHCP-provided DNS on existing Wi-Fi and Ethernet profiles with
  Cloudflare Families malware-and-adult-content resolvers by default.
- Optionally uses a parent-supplied NextDNS configuration ID instead of
  Cloudflare; no ID is embedded and no third-party resolver binary is installed.
- Configures IPv4 and IPv6 resolver addresses and the root routing domain.
- Uses opportunistic authenticated DNS-over-TLS with Cloudflare. NextDNS uses
  strict DNS-over-TLS because its TLS server name carries the configuration ID;
  it does not silently fall back to unidentified plaintext DNS.
- Strict NextDNS DNS-over-TLS is applied at the system-resolved level, so every
  active link uses it. On networks that block outbound TCP port 853 the resolver
  cannot be reached; recovery switches back to the Cloudflare default.
- Reapplies policy to new NetworkManager connections through a dispatcher.
- Sets `ipv4.dns-priority` and `ipv6.dns-priority` to the lowest possible
  value, `-2147483648`, on each managed connection. Lower values win in
  NetworkManager's DNS selection, so the filtered resolvers take precedence
  over DHCP-provided ones on the same link. A connection or VPN that routes
  traffic away from the local resolver, or that installs its own resolver
  outside this configuration, still bypasses the filtered resolvers.
- Clears `FallbackDNS` in both resolver drop-ins, so there is no unfiltered
  backup resolver. On a network that blocks TCP port 853, resolution either
  downgrades to plaintext or fails outright instead of falling back to a
  provider outside the selected filter.
- Disables Vivaldi Secure DNS so the browser uses the filtered system resolver.
- Allows the child to connect to or disconnect from Wi-Fi through the restricted
  panel; newly created Wi-Fi profiles receive Family DNS when activated.

DNS filtering does not inspect page content and cannot guarantee that every
unsuitable site is blocked. Applications implementing DNS-over-HTTPS or a VPN
can bypass host resolver policy unless separately restricted.

NextDNS receives the device's DNS queries and source IP. Dashboard query logging,
retention, storage location, and optional blocked-query logging are controlled by
the parent in the selected NextDNS configuration and should be reviewed before
opt-in. This integration does not send a device name or install NextDNS's root
certificate. The configuration ID is visible in effective resolver settings to
local users even though its local source file is root-only.

## Power

- Does not configure TuneD or `power-profiles-daemon` at all. No script in this
  repository sets, changes, or verifies a power profile; `audit.sh` only
  reports which of those packages and services are present. Treat an expected
  `powersave` profile as an unverified precondition and check it yourself with
  `tuned-adm active` or `powerprofilesctl get` during the audit.
- Disables suspend, hibernate, hybrid sleep, and suspend-then-hibernate
  system-wide, not only for the child. `deploy.sh` installs
  `/etc/systemd/logind.conf.d/90-chalkboard-power.conf` and
  `/etc/systemd/sleep.conf.d/90-chalkboard-disable-sleep.conf` and masks the
  sleep targets with `systemctl mask`. The parent loses suspend too, and only
  `rollback.sh` restores it; there is no per-account or per-session opt-out.
- Requests clean shutdown for the power key and any detected lid switch
  system-wide, through the same logind drop-in.
- Configures the same shutdown behavior in the child PowerDevil profile. This
  half is child-scoped: `deploy.sh` writes `powerdevilrc` into the child's own
  `.config`.
- Shows charge state and brightness controls through Plasma's battery widget.
- Provides confirmed on-screen shutdown and restart for tablets and detachables.

The HP Elite x2 is detachable and may not generate a lid event. Always close
documents before testing the cover or power button. Because the sleep policy is
system-wide, test lid and power-key behavior last, and be aware that the
parent's own suspend is already gone.

Its touchscreen, Wacom pen/finger input, touchpad, lid switch, tablet-mode
switches, 2736x1824 internal display, and active orientation sensor service were
confirmed during development. Plasma Desktop remains the session so the same
device works normally when its keyboard is attached.

## Intentionally excluded

- ScratchJr: no supported official web application was confirmed. The
  [candidate research and acceptance criteria](scratchjr-web-research.md)
  explain why unofficial browser ports are not installed.
- Khan Academy Kids: supported on iOS, Android, and Amazon Fire, but not as a
  Fedora or browser app.
- Duolingo ABC: supported on iPhone/iPad and Android, but not as a Fedora or
  browser app.
- Weather remains outside the default baseline because it discloses an
  approximate location to a network provider and conflicts with offline-first
  operation. See the deployment runbook for the explicit opt-in.
- Minecraft timing, retro CD-ROM support, and 3D Movie Maker: roadmap projects,
  not part of the initial Fedora baseline. Generic parent-owned Windows
  installers have a separate optional Wine workflow, not a title-specific
  compatibility profile.
- BIOS changes: cannot be safely generalized or automated from this repository.
