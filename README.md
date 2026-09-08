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

## Project status

The source video and initial handoff are requirements inputs, not executable
specifications. Claims are validated against current platform behavior before
they become automation. The Fedora implementation is pinned to Fedora 43 and is
ready for its first complete hardware test; it is not yet a stable release.

See [features](docs/features.md), [recovery](docs/recovery.md), the
[roadmap](docs/roadmap.md), and [technical sources](docs/sources.md) for
important boundaries and limitations.
