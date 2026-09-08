# Fedora feature set

## Accounts and login

- Creates or verifies a dedicated `chalkboard` account.
- Keeps the child account out of `wheel` and `sudo`.
- Locks password authentication for the child account.
- Configures SDDM to autologin to the Plasma Wayland session after boot.
- Leaves the parent account and its desktop settings unchanged.
- Disables automatic screen locking because a password-locked autologin account
  could not unlock itself.
- Disables KDE Wallet and Vivaldi password saving to avoid wallet prompts or
  secret-service failures in a passwordless autologin session.

## Desktop

- Uses Plasma Desktop's built-in automatic tablet mode rather than a custom
  shell or custom QML.
- Uses KDE's full-screen Application Dashboard and an Icons-only Task Manager
  with a small set of favorites and normal running-window switching.
- Keeps ordinary Dashboard application browsing, but removes recent documents,
  extra search runners, and Konsole from the child-facing menu.
- Curates the Application Dashboard to an explicit allowlist: every installed
  application that is not in `config/fedora/app-allowlist.txt` is hidden. This
  removes Fedora/KDE system tools, the software center, email/chat clients, and
  development utilities while keeping the curated applications, the browser, and
  Dolphin.
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
- Disables panel editing and desktop scripting through immutable KDE policy.
- Preserves normal application behavior, file dialogs, multitasking, and window
  management.
- Attempts to disable tap-to-click for each touchpad exposed by KWin during the
  first child session. Detachable hardware may expose no touchpad while its
  keyboard cover is disconnected.
- Optionally adds Fedora's packaged KDE weather widget only after a parent
  explicitly selects the NOAA provider and a station. Weather remains disabled
  by default, can change only before `finalize-lockdown.sh`, and is removed
  cleanly when disabled.
  by default and does not alter baseline panel provisioning.

KDE policy keeps the simplified layout consistent; it is not a security sandbox.
The separate non-admin account is the primary privilege boundary.

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

Vivaldi receives mandatory policy that disables browser DNS-over-HTTPS,
extensions, guest mode, additional browser profiles, incognito mode, and
developer tools. Google SafeSearch and YouTube Restricted Mode are requested
through Chromium policy, and browser password saving is disabled. Effective
policy must be confirmed at `vivaldi://policy` during graphical testing.

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

- Keeps TuneD's existing `powersave` profile.
- Disables suspend, hibernate, hybrid sleep, and suspend-then-hibernate.
- Masks the corresponding systemd sleep targets.
- Requests clean shutdown for the power key and any detected lid switch.
- Configures the same shutdown behavior in the child PowerDevil profile.
- Shows charge state and brightness controls through Plasma's battery widget.
- Provides confirmed on-screen shutdown and restart for tablets and detachables.

The HP Elite x2 is detachable and may not generate a lid event. Always close
documents before testing the cover or power button.

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
