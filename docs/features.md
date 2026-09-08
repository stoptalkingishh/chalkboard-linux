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

- Creates one large bottom panel with approved application launchers, running
  windows, device controls, and a clock.
- Removes the application launcher and full system tray.
- Adds a task manager for normal window switching without restoring the
  application launcher.
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

KDE policy keeps the simplified layout consistent; it is not a security sandbox.
The separate non-admin account is the primary privilege boundary.

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
  Cloudflare Families malware-and-adult-content resolvers.
- Configures IPv4 and IPv6 resolver addresses and the root routing domain.
- Uses opportunistic authenticated DNS-over-TLS for reliability; plaintext
  fallback still goes to the same Family resolver addresses.
- Reapplies policy to new NetworkManager connections through a dispatcher.
- Disables Vivaldi Secure DNS so the browser uses the filtered system resolver.
- Allows the child to connect to or disconnect from Wi-Fi through the restricted
  panel; newly created Wi-Fi profiles receive Family DNS when activated.

DNS filtering does not inspect page content and cannot guarantee that every
unsuitable site is blocked. Applications implementing DNS-over-HTTPS or a VPN
can bypass host resolver policy unless separately restricted.

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

## Intentionally excluded

- ScratchJr: no supported official web application was confirmed.
- Khan Academy Kids: supported on iOS, Android, and Amazon Fire, but not as a
  Fedora or browser app.
- Duolingo ABC: supported on iPhone/iPad and Android, but not as a Fedora or
  browser app.
- Weather widget: requires a location and third-party data provider and conflicts
  with the offline-first default.
- Minecraft timing and 3D Movie Maker remain roadmap projects. Generic
  parent-owned Windows installers have a separate optional Wine workflow, not a
  title-specific compatibility profile or part of the initial Fedora baseline.
- BIOS changes: cannot be safely generalized or automated from this repository.
