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

## Roll back configuration

From the repository checkout, run:

```bash
sudo bash scripts/fedora/rollback.sh
sudo reboot
```

Rollback restores files saved before the first deployment, restores original
NetworkManager profile files, unmasks sleep targets, reloads NetworkManager, and
restarts `systemd-resolved`.

Installed RPMs, Flatpaks, the Flathub remote, and the `chalkboard` account are
retained to avoid destructive package or account removal. They can be removed
manually after confirming no data is needed.

## DNS failure

NextDNS uses strict DNS-over-TLS, so networks that block TCP port 853 or captive
portals that require DNS before sign-in can prevent resolution. From an offline
repository checkout, switch back to Cloudflare without rerunning full deployment:

```bash
sudo bash scripts/fedora/configure-dns.sh
sudo bash scripts/fedora/verify.sh
```

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

Full rollback restores the resolver drop-in, NextDNS profile file, dispatcher,
installed DNS helper, and NetworkManager profiles from before the first
Chalkboard DNS configuration. It does not alter or delete the parent's NextDNS
account or cloud-side logs.

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
