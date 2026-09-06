# Recovery

## Parent access

The child panel intentionally has no network or settings controls. Use one of
these parent paths:

- SSH into the device with the parent key.
- Press `Ctrl+Alt+F3`, log in as the parent, and use the text console.
- Log out to SDDM and select the parent account. The child has no password and
  cannot log back in manually; reboot restores child autologin.

The parent account is not subject to `/etc/xdg/chalkboard` policy.

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

If name resolution fails but SSH by IP still works, roll back. For a temporary
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

## Failed first login

Inspect:

```bash
sudo cat /home/chalkboard/.local/state/chalkboard/first-login.log
sudo journalctl -b _UID=$(id -u chalkboard)
```

Do not run `finalize-lockdown.sh` until the `plasma-provisioned` marker exists
and the panel is visibly correct.
