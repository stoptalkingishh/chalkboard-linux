# Chalkboard

Chalkboard is a cross-platform toolkit for setting up child-friendly family
devices. It favors creation, computer literacy, predictable limits, and parent
ownership over engagement-driven feeds.

This project does not build a new operating system. It applies a shared family
device policy through platform-specific setup guides and automation.

## Platform roadmap

| Platform | Management model | Status |
| --- | --- | --- |
| Fedora KDE Plasma | Audited, reversible local automation | Test deployment |
| iPhone and iPad | Apple Family Sharing and Screen Time guide | Planned |
| Fire tablet | On-device settings with optional ADB helpers | Planned |

The first supported Linux target is Fedora KDE Plasma. Other Linux desktops and
distributions are out of scope until the Fedora workflow is tested on real
hardware.

## Safety model

- The parent account remains the only administrator.
- Deployment disables suspend system-wide, so the parent loses it too; only
  full rollback restores it.
- A child uses a separate unprivileged account.
- Changes must be inspectable, repeatable, and reversible.
- Network filtering is a useful guardrail, not a complete security boundary.
- Parent recovery access must be tested before the child interface is locked.
- Credentials and device-specific secrets must never be committed.

See [the architecture](docs/architecture.md) and the
[Fedora rollout](docs/platforms/fedora-kde.md) before applying changes.

## Fedora quick start

Run the read-only audit locally on the Fedora device:

```bash
bash scripts/fedora/audit.sh
```

The audit prints system capabilities but does not alter the device. Do not post
its complete output publicly without reviewing the hardware fields. Follow the
full [deployment runbook](docs/deployment.md) before making changes.

After reviewing the audit, create the unprivileged account from an administrator
shell:

```bash
sudo bash scripts/fedora/create-child-user.sh chalkboard
```

The account is created with a locked password and cannot log in until a parent
explicitly configures its authentication or SDDM autologin.

Apply stage one:

```bash
sudo bash scripts/fedora/deploy.sh
```

Cloudflare Family DNS remains the default. A parent can instead opt in to a
NextDNS configuration by following the DNS section of the deployment runbook;
no NextDNS identifier is included in this repository.

After reboot and first-login provisioning, apply the immutable child policy:

```bash
sudo bash scripts/fedora/finalize-lockdown.sh
sudo reboot
```

Finalization is effectively one-way for two features. Configure the optional
[weather widget](docs/deployment.md#optional-weather) and the
[screen-time schedule](docs/screen-time.md) before running
`finalize-lockdown.sh`. After it runs, `chalkboard-weather` refuses changes
because the finalized marker file exists, and the child's Dashboard is curated
to `config/fedora/app-allowlist.txt` with no un-hide command. Full rollback is
the only way to recover from a wrong weather location or app set. Screen time
can still be installed and enabled afterwards, since it is a separate root-only
framework, but installing it after lockdown means working over SSH or the text
console rather than the child desktop.

Finalization also curates the app menu. To change the child's applications
afterwards, edit `config/fedora/app-allowlist.txt` and rerun
`finalize-lockdown.sh`.

An optional parent-enabled mode can replace the child Plasma session with a
single GCompris session. It is installed but disabled by default; see the
[deployment runbook](docs/deployment.md#optional-single-app-gcompris-mode).

## Project status

The source video and initial handoff are requirements inputs, not executable
specifications. Claims are validated against current platform behavior before
they become automation. The Fedora implementation is pinned to Fedora 43 and is
ready for its first complete hardware test; it is not yet a stable release.

See [features](docs/features.md), [recovery](docs/recovery.md), the
[roadmap](docs/roadmap.md), and [technical sources](docs/sources.md) for
important boundaries and limitations.

## Testing

Three layers, and they are not interchangeable. The distinction matters: two
real bugs in the app-menu verifier passed the fixture-based layer and were caught
only by the container layer, because the fixtures and the bugs happened to share
the same wrong assumption about Plasma's config format.

| Layer | Command | Covers |
|---|---|---|
| Static and unit | `bash tests/static.sh` | ShellCheck over every script, `desktop-file-validate`, JSON validity, DNS validation, launcher/allowlist consistency, and unit tests for the screen-time, weather, retro, rollback, and app-menu logic. Needs `shellcheck`, `desktop-file-utils`, `python3`, and `node`. This is what CI runs. |
| Fedora container | see [tests/fedora-container](tests/fedora-container/README.md) | The curation and verification scripts against a real Fedora 43 root filesystem and its real desktop file database, with a real unprivileged child account. Not in CI, because the image build takes minutes. |
| Device | `sudo bash scripts/fedora/verify.sh` | The provisioned laptop: package state, DNS, tablet mode, panel provisioning, and app-menu curation. |

Only the device layer can confirm anything graphical. The container has no
display server, no D-Bus, and no Plasma, so it cannot establish that the kiosk
policy is enforced; that the panel, Dashboard, touch input, or virtual keyboard
work; or that `org.kde.plasma.kickerdash` consumes the `hiddenApplications` key
the way the code assumes. See the container README for the full list.

Optional Fedora downtime schedules are installed and enabled separately. See
[Fedora screen time](docs/screen-time.md); the framework is disabled by default
and its example config contains no schedule.

Parents may separately opt into the [retro-game framework](docs/retro-games.md)
for lawfully owned media. It is not part of the default deployment, includes no
game assets or circumvention tooling, and makes no title compatibility claims.
