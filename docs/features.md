# Fedora feature set

## Accounts and login

- Creates or verifies a dedicated `chalkboard` account.
- Keeps the child account out of `wheel` and `sudo`.
- Locks password authentication for the child account.
- Configures SDDM to autologin to the Plasma Wayland session after boot.
- Leaves the parent account and its desktop settings unchanged.
- Disables automatic screen locking because a password-locked autologin account
  could not unlock itself.

## Desktop

- Creates one large bottom panel with approved application launchers and a clock.
- Removes the application launcher, task manager, and system tray.
- Disables KRunner and application-launcher shortcuts in the child session.
- Disables panel editing, desktop scripting, shell access, and unregistered
  desktop-file execution through immutable KDE kiosk policy.
- Attempts to disable tap-to-click for each touchpad exposed by KWin during the
  first child session. Detachable hardware may expose no touchpad while its
  keyboard cover is disconnected.

KDE kiosk settings are cooperative desktop restrictions, not a security sandbox.
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
- Teach Your Monster as a Vivaldi app window
- A general Vivaldi browser launcher

Vivaldi receives mandatory policy that disables browser DNS-over-HTTPS,
extensions, guest mode, additional browser profiles, incognito mode, and
developer tools. Google SafeSearch and YouTube Restricted Mode are requested
through Chromium policy. Effective policy must be confirmed at
`vivaldi://policy` during graphical testing.

## Network

- Replaces DHCP-provided DNS on existing Wi-Fi and Ethernet profiles with
  Cloudflare Families malware-and-adult-content resolvers.
- Configures IPv4 and IPv6 resolver addresses and the root routing domain.
- Uses opportunistic authenticated DNS-over-TLS for reliability; plaintext
  fallback still goes to the same Family resolver addresses.
- Reapplies policy to new NetworkManager connections through a dispatcher.
- Disables Vivaldi Secure DNS so the browser uses the filtered system resolver.

DNS filtering does not inspect page content and cannot guarantee that every
unsuitable site is blocked. Applications implementing DNS-over-HTTPS or a VPN
can bypass host resolver policy unless separately restricted.

## Power

- Keeps TuneD's existing `powersave` profile.
- Disables suspend, hibernate, hybrid sleep, and suspend-then-hibernate.
- Masks the corresponding systemd sleep targets.
- Requests clean shutdown for the power key and any detected lid switch.
- Configures the same shutdown behavior in the child PowerDevil profile.

The HP Elite x2 is detachable and may not generate a lid event. Always close
documents before testing the cover or power button.

## Intentionally excluded

- ScratchJr: no supported official web application was confirmed.
- Weather widget: requires a location and third-party data provider and conflicts
  with the offline-first default.
- Minecraft timing, retro CD-ROM support, and 3D Movie Maker: roadmap projects,
  not part of the initial Fedora baseline.
- BIOS changes: cannot be safely generalized or automated from this repository.
