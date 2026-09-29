# Recovery

## Parent access

The child panel has Wi-Fi controls but no general system settings. Use one of
these parent paths for administration:

- SSH into the device with the parent key.
- Press `Ctrl+Alt+F3`, log in as the parent, and use the text console.
- Log out to SDDM and select the parent account. The child has no password and
  cannot log back in manually; reboot restores child autologin.

The parent account is not subject to `/etc/xdg/chalkboard` policy.

If optional screen-time downtime is active, the parent account remains usable.
Run `sudo chalkboard-screen-time disable` from SSH or the text console to stop
the timer and restore the child account's prior expiry. See the dedicated
[screen-time recovery procedure](screen-time.md#disable-and-recover).

## Disable GCompris mode

From SSH, or after pressing `Ctrl+Alt+F3` and logging in as the parent, run:

```bash
sudo /usr/local/sbin/chalkboard-gcompris-mode disable
sudo reboot
```

The command is available outside the repository checkout and is idempotent. It
removes the optional SDDM override before its state marker, so an interrupted
disable falls back to the normal Plasma autologin. If the session crashes before
recovery, `Relogin=false` leaves SDDM at its greeter rather than looping; use SSH,
the text console, or reboot and then disable the mode.

If the helper itself is damaged, the equivalent parent-only emergency action is:

```bash
sudo rm -f /etc/sddm.conf.d/95-chalkboard-gcompris.conf
sudo rm -f /var/lib/chalkboard/gcompris-mode-enabled
sudo reboot
```

These files are root-owned. Removing them does not modify the child or parent
Plasma configuration.

## Roll back configuration

From the repository checkout, run:

```bash
sudo bash scripts/fedora/rollback.sh
sudo reboot
```

Rollback restores files saved before the first deployment, restores original
NetworkManager profile files, unmasks sleep targets, reloads NetworkManager, and
restarts `systemd-resolved`. It also disables optional GCompris mode before
restoring the original SDDM configuration.

Installed RPMs, Flatpaks, the Flathub remote, and the `chalkboard` account are
retained to avoid destructive package or account removal. They can be removed
manually after confirming no data is needed.

Full rollback restores the pre-deployment Plasma applet configuration and
`/etc/chalkboard/weather.conf`, so an enabled Chalkboard weather widget is also
removed. The optional `kdeplasma-addons` RPM is retained with other packages.

## Weather recovery

Configure weather with `chalkboard-weather enable` before running
`finalize-lockdown.sh`. After finalization the command refuses further changes
because `scripts/fedora/weather.sh` checks for the marker file
`/var/lib/chalkboard/finalized`, which `finalize-lockdown.sh` creates; the
refusal is a marker test, not a consequence of the locked shell. Full rollback
remains the recovery path for a finalized installation.

`scripts/fedora/weather-session.sh` separately assumes the immutable policy may
block the D-Bus panel scripting that adds or removes the widget, and exits
quietly if that call fails. Whether `plasma-desktop/scripting_console=false`
actually blocks `org.kde.PlasmaShell.evaluateScript` over D-Bus is not covered
by any automated test and requires graphical verification.

Weather changes are applied at child login, not directly from the parent shell.
For a provider failure or privacy rollback before finalization, run:

```bash
sudo chalkboard-weather disable
sudo reboot
```

This immediately removes the configured location from
`/etc/chalkboard/weather.conf`; the reboot removes the tagged widget. Inspect a
failed reconciliation with:

```bash
sudo cat /home/chalkboard/.local/state/chalkboard/weather.log
rpm -q kdeplasma-addons
grep '^Enabled=' /etc/chalkboard/weather.conf
```

If the log reports that it cannot identify the baseline panel, do not edit
`plasma-org.kde.plasma.desktop-appletsrc` by hand. Disable weather first. Use
full rollback if the baseline panel itself is damaged.

## App-menu curation recovery

Curation is as irreversible as weather and has no dedicated command to undo it.
`finalize-lockdown.sh` runs `scripts/fedora/curate-app-menu.sh`, which writes a
static list of hidden application IDs into the child's kickerdash
configuration. There is no un-hide command.

To change the set of applications the child can see, edit
`config/fedora/app-allowlist.txt` in the repository checkout and re-run
finalization as the parent:

```bash
sudo bash scripts/fedora/finalize-lockdown.sh
sudo reboot
```

The script requires the first-login `plasma-provisioned` marker and is safe to
repeat. It recomputes the hidden list from the allowlist and the applications
currently installed, so an entry added to the allowlist reappears and one
removed disappears. Because the hidden list is a snapshot, an application
installed after finalization is not in it and stays visible until finalization
runs again.

Full rollback restores the pre-deployment applet configuration, which removes
the curation entirely.

## DNS failure

NextDNS uses strict DNS-over-TLS, so networks that block TCP port 853 or captive
portals that require DNS before sign-in can prevent resolution. From an offline
repository checkout, switch back to Cloudflare without rerunning full deployment:

```bash
sudo bash scripts/fedora/configure-dns.sh
sudo bash scripts/fedora/verify.sh
```

Cloudflare can also fail, but differently. It uses opportunistic
DNS-over-TLS, so a network that blocks TCP port 853 normally downgrades to
plaintext DNS rather than failing outright: resolution continues, but
unencrypted, and there is no unfiltered fallback resolver to restore either. If
Cloudflare itself is unreachable or the network intercepts DNS, use the same
temporary diagnostic and rollback steps below.

Switching to Cloudflare is itself a change that is easy to mistake for the
original state. It renames the NextDNS profile file instead of deleting it, and
re-running `configure-dns.sh` does not remove that renamed copy. See the limits
noted under the rollback description below.

If name resolution still fails but SSH by IP works, roll back. For a temporary
parent-only diagnostic, inspect:

```bash
resolvectl status
nmcli connection show --active
systemctl status systemd-resolved
```

Do not delete NetworkManager profiles. Their originals are stored under:

```text
/var/lib/chalkboard/backup/files/etc/NetworkManager/system-connections/
```

Full rollback restores the resolver drop-in, the NextDNS profile file as it
existed before the first Chalkboard DNS configuration, the dispatcher, the
installed DNS helper, and NetworkManager profiles from before the first
Chalkboard DNS configuration. It does not alter or delete the parent's NextDNS
account or cloud-side logs.

Two limits are worth knowing before relying on this path:

- Switching back to Cloudflare renames `/etc/chalkboard/nextdns-profile` to
  `nextdns-profile.disabled-<timestamp>` rather than deleting it. That renamed
  file is never backed up, so full rollback does not remove it. It is
  root-owned and mode `0600`, and `apply-family-dns.sh` only enables NextDNS
  when the original handover file is present, so it is inert. Remove it
  manually if the parent wants the directory returned to its original state.
- `configure-dns.sh` calls `backup_file` on the `/etc/NetworkManager/
  system-connections` directory, but `rollback.sh` walks only regular files
  under the backup tree. If that directory was empty at first deployment, only a
  `.missing` marker was saved and the profile restore silently does nothing.
  Confirm the backup directory is non-empty before relying on it:

```bash
sudo find /var/lib/chalkboard/backup/files/etc/NetworkManager \
  -type f -print
```

If that prints nothing, keep your own copy of the connection files before
relying on the automatic restore.

## Failed first login

Inspect:

```bash
sudo cat /home/chalkboard/.local/state/chalkboard/first-login.log
sudo journalctl -b _UID=$(id -u chalkboard)
```

Do not run `finalize-lockdown.sh` until the `plasma-provisioned` marker exists
and the panel is visibly correct.

If child applications report permission errors, verify that the dedicated home
is entirely owned by the child account:

```bash
sudo find /home/chalkboard ! -user chalkboard -print
```
