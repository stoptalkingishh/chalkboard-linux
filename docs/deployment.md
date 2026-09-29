# Fedora deployment runbook

This runbook currently supports Fedora Linux 43 KDE Plasma Desktop Edition and
the fixed child username `chalkboard`.

## Before deployment

1. Back up irreplaceable files.
2. Verify local login and `sudo` for the parent account.
3. Verify SSH key access for the parent account.
4. Keep the machine connected to power.
5. Close child-session documents before power behavior is tested.

Run the read-only audit:

```bash
bash scripts/fedora/audit.sh
```

Create or enforce the child account policy:

```bash
sudo bash scripts/fedora/create-child-user.sh chalkboard
```

## Stage one

```bash
sudo bash scripts/fedora/deploy.sh
```

This uses Cloudflare Family DNS by default. To opt in to NextDNS, first create
and review a configuration at `my.nextdns.io`, including its parental-control,
denylist, and logging settings. Then copy its six-character configuration ID
from the setup page into a shell variable and explicitly pass it to deployment:

```bash
read -r -p 'NextDNS configuration ID: ' NEXTDNS_PROFILE_ID
sudo bash scripts/fedora/deploy.sh --nextdns-profile "$NEXTDNS_PROFILE_ID"
unset NEXTDNS_PROFILE_ID
```

The ID must contain exactly six lowercase hexadecimal characters. It is not an
account password, but it identifies the family's resolver configuration and
must not be committed to this repository. Chalkboard stores it locally in
`/etc/chalkboard/nextdns-profile`, owned by root with mode `0600`. The setup uses
Fedora's existing NetworkManager and `systemd-resolved`; it does not download or
install the NextDNS CLI or a custom root certificate.

Stage one performs the following operations:

- Installs the application catalog, Vivaldi, and CuteMaze.
- Saves original managed files under `/var/lib/chalkboard/backup`.
- Applies the selected Family DNS backend to NetworkManager Wi-Fi and Ethernet
  profiles.
- Installs Vivaldi managed policy.
- Configures shutdown behavior and disables sleep system-wide, for every
  account including the parent's, and enables autologin. Only `rollback.sh`
  restores suspend.
- Curates the child Dashboard to the allowlist at finalization, not here.
- Prepares launchers, PowerDevil settings, and the first-login provisioner.
- Stages but does not activate immutable KDE restrictions.
- Installs the optional weather controls, but leaves weather disabled and does
  not install or add the widget.
- Installs Cage and the optional GCompris session without enabling it.

When it succeeds, reboot:

```bash
sudo reboot
```

SDDM automatically starts `chalkboard`. Wait up to two minutes for the panel to
appear. The first-login process writes:

```text
/home/chalkboard/.local/state/chalkboard/plasma-provisioned
```

Its log is:

```text
/home/chalkboard/.local/state/chalkboard/first-login.log
```

Do not finalize if the panel does not contain the expected launchers and clock.
Use the recovery guide to inspect the log first.

## Optional features

None of these are part of the default baseline. Each is installed or documented
separately and is safe to skip:

- [Optional weather](#optional-weather) - keyless NOAA widget, must be
  configured before finalization
- [Optional single-app GCompris mode](#optional-single-app-gcompris-mode) -
  parent-enabled Cage session, installed but disabled by stage one
- Screen time - see [screen-time.md](screen-time.md); installed with
  `scripts/fedora/install-screen-time.sh`, disabled until a parent configures
  and enables it
- App-menu curation - applied by `finalize-lockdown.sh`; see
  [Finalize](#finalize)
- [Retro games](retro-games.md) - optional, not run by `deploy.sh`

## Optional weather

Weather is disabled by default. A parent may explicitly enable it after stage
one by supplying an exact NOAA station name and state or territory code:

```bash
sudo chalkboard-weather enable --provider noaa \
  --location "EXACT NOAA STATION NAME, ST"
sudo reboot
```

Do not use the example text as a location. The value must match a station in
`/usr/share/plasma/weather/noaa_station_list.xml`; station names can contain
additional commas. This release intentionally supports only the packaged NOAA
provider. It needs no API key and is useful only for locations covered by the
US National Weather Service.

Enabling installs Fedora's `kdeplasma-addons` package and adds KDE's stock
`org.kde.plasma.weather` widget immediately before the clock at the next child
login. It does not change `panel.js`. Repeating the command updates the same
managed widget rather than adding another one.

Privacy review: the widget contacts `api.weather.gov` over HTTPS at least every
30 minutes. NOAA receives the device's public IP, the selected station, station
coordinates, and county/forecast-zone requests. The station is also stored in
root-owned, system-readable configuration and the child's Plasma configuration.
No browser geolocation, GPS lookup, API key, or credential is used. Weather is
not appropriate when the installation must remain offline-first or disclosing
the approximate location is unacceptable.

Disable it and erase the location from Chalkboard's system configuration with:

```bash
sudo chalkboard-weather disable
sudo reboot
```

Disable is also idempotent. It removes only the widget tagged as managed by
Chalkboard; it does not rebuild the panel or remove unrelated weather widgets.
The RPM remains installed, consistent with the repository's non-destructive
rollback policy.

Configure weather before immutable policy is finalized. After
`finalize-lockdown.sh` runs, `chalkboard-weather` refuses changes because
`weather.sh` finds the marker file `/var/lib/chalkboard/finalized` that
finalization creates. This is a marker test in the script, not a consequence of
the locked shell rejecting D-Bus panel scripting; that separate question is
untested and needs graphical verification. Full rollback is the only recovery
path for a finalized installation.

## Parent commissioning

Complete online-service setup in the child session before immutable lockdown:

1. Open Vivaldi and complete its welcome flow.
2. Open `vivaldi://policy` and confirm every Chalkboard policy reports `OK`.
3. In Vivaldi settings, enable its built-in tracker and ad blocking.
4. Open Teach Your Monster, create a free home account, confirm the parent email,
   and create a child player using a nickname.
5. Close and reopen Teach Your Monster; confirm the launcher enters the reading
   game rather than account setup.
6. Open Coolmath Games and review its consent and advertising behavior.
7. Confirm Kid Pix and every local application starts correctly.

Vivaldi's `--no-first-run` switch does not suppress Vivaldi's own welcome pages.
The repository intentionally does not edit undocumented internal preferences to
bypass them because those preferences are version-sensitive.

## Finalize

Connect as the parent over SSH or switch to a local text console, then run:

```bash
sudo bash scripts/fedora/finalize-lockdown.sh
sudo reboot
```

The second reboot loads immutable child-only KDE policy. The same command also
curates the child Application Dashboard to `config/fedora/app-allowlist.txt`:
every installed application that is not in that file is hidden. There is no
separate curation step and no un-hide command.

To change the child's app set afterwards, edit
`config/fedora/app-allowlist.txt` in the repository checkout and rerun
`finalize-lockdown.sh` followed by a reboot. The hidden list is recomputed from
the allowlist and the currently installed applications, so the command is safe
to repeat. Because it is a snapshot taken at finalization time, an application
installed after that point is not hidden and remains visible to the child
until finalization runs again. Full rollback restores the pre-deployment applet
configuration and removes the curation entirely. See the
[app-menu curation recovery procedure](recovery.md#app-menu-curation-recovery).

Run verification as the parent:

```bash
sudo bash scripts/fedora/verify.sh
```

Also verify graphically:

1. The panel contains Application Dashboard, curated favorites, running windows,
   device controls, power, and a clock.
2. Meta, `Alt+F1`, `Alt+F2`, and `Alt+Space` do not open a launcher.
3. Right-clicking the desktop or panel cannot enter edit mode.
4. Every launcher starts successfully.
5. `vivaldi://policy` reports the Chalkboard policies with status `OK`.
6. `https://malware.testcategory.com/` is blocked.
7. `https://nudity.testcategory.com/` is blocked.
8. The parent account still has its normal desktop and administrative access.
9. Wi-Fi can disconnect and reconnect, and `resolvectl status` still shows only
   the selected Family DNS backend afterward. For NextDNS, also open
   `https://test.nextdns.io` and confirm `status` is `ok`, `protocol` is `DOT`,
   and the expected profile is reported.
10. The Power launcher asks for confirmation before restart or shutdown.
11. `Super+E` opens Dolphin, while `Ctrl+Alt+T` does not open a terminal.
12. Open applications appear in the task manager and can be switched normally.
13. Touching a text field opens Plasma Keyboard when the hardware keyboard is
    detached or tablet mode is active.
14. Rotating the tablet rotates the internal display when the hardware sensor
    reports orientation changes.
15. The internal display uses 175% scaling and remains usable with the keyboard
    attached.
16. If weather was enabled, the selected location appears immediately before
    the clock and `api.weather.gov` requests succeed. If disabled, no weather
    widget appears.

Test lid and power-key shutdown last because a successful test powers off the
machine.

## Change DNS backend

DNS selection can be changed independently and safely rerun. To disable NextDNS
and return to the default Cloudflare Family DNS, run:

```bash
sudo bash scripts/fedora/configure-dns.sh
sudo bash scripts/fedora/verify.sh
```

To select a different NextDNS configuration, rerun `configure-dns.sh` with
`--nextdns-profile` as shown above. Existing Wi-Fi and Ethernet connections are
modified in place; the dispatcher applies the same selection to new profiles.
The first saved pre-Chalkboard state remains the rollback source across reruns.

## Optional single-app GCompris mode

Only enable this after testing parent SSH and local-console login. The normal
desktop remains the default until a parent runs:

```bash
sudo /usr/local/sbin/chalkboard-gcompris-mode enable
sudo reboot
```

The command is idempotent. It checks that deployment, Cage, GCompris, the
session files, and the unprivileged child account are present. It then installs
a higher-priority SDDM autologin override atomically. It does not restart SDDM or
terminate a current session.

After reboot, SDDM starts a Cage Wayland session as `chalkboard`; Cage starts
only `gcompris-qt --fullscreen --enable-kioskmode`. GCompris's kiosk option hides
its normal quit and configuration paths. If GCompris or Cage exits, SDDM returns
to the greeter because `Relogin=false`; it does not repeatedly restart a broken
session. The next boot tries the session again.

Verify the configured state from a parent shell:

```bash
sudo /usr/local/sbin/chalkboard-gcompris-mode status
bash scripts/fedora/verify.sh
```

Also test that GCompris occupies the display, ordinary launcher and window
switching shortcuts expose no host desktop, audio works, activities save state,
the power key still performs the configured clean shutdown, and reboot returns
to GCompris. Test `Ctrl+Alt+F3` parent login before relying on local recovery.

Disable the mode from SSH or a parent text console:

```bash
sudo /usr/local/sbin/chalkboard-gcompris-mode disable
sudo reboot
```

Disablement removes only the optional override and marker, revealing the normal
Plasma autologin configuration. It is safe to repeat. Full rollback also
disables this mode before restoring pre-deployment files.
