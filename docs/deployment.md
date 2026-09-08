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

Stage one performs the following operations:

- Installs the application catalog, Vivaldi, and CuteMaze.
- Saves original managed files under `/var/lib/chalkboard/backup`.
- Applies Family DNS to NetworkManager Wi-Fi and Ethernet profiles.
- Installs Vivaldi managed policy.
- Configures shutdown behavior, disables sleep, and enables autologin.
- Prepares launchers, PowerDevil settings, and the first-login provisioner.
- Stages but does not activate immutable KDE restrictions.
- Installs the optional weather controls, but leaves weather disabled and does
  not install or add the widget.

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
`finalize-lockdown.sh` runs, the locked shell no longer accepts the D-Bus panel
scripting that reconciliation uses, so `chalkboard-weather` refuses changes and
full rollback is the only recovery path for a finalized installation.

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

The second reboot loads immutable child-only KDE policy. Run verification as the
parent:

```bash
bash scripts/fedora/verify.sh
```

Also verify graphically:

1. The panel contains approved launchers, running windows, device controls,
   power, and a clock.
2. Meta, `Alt+F1`, `Alt+F2`, and `Alt+Space` do not open a launcher.
3. Right-clicking the desktop or panel cannot enter edit mode.
4. Every launcher starts successfully.
5. `vivaldi://policy` reports the Chalkboard policies with status `OK`.
6. `https://malware.testcategory.com/` is blocked.
7. `https://nudity.testcategory.com/` is blocked.
8. The parent account still has its normal desktop and administrative access.
9. Wi-Fi can disconnect and reconnect, and `resolvectl status` still shows only
   Cloudflare Family DNS afterward.
10. The Power launcher asks for confirmation before restart or shutdown.
11. `Super+E` opens Dolphin, while `Ctrl+Alt+T` does not open a terminal.
12. Open applications appear in the task manager and can be switched normally.
13. If weather was enabled, the selected location appears immediately before
    the clock and `api.weather.gov` requests succeed. If disabled, no weather
    widget appears.

Test lid and power-key shutdown last because a successful test powers off the
machine.
