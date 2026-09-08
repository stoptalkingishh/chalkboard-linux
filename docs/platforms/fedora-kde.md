# Fedora KDE Plasma rollout

Fedora KDE Plasma is the first implementation target. Support begins with the
exact Fedora and Plasma versions reported by `scripts/fedora/audit.sh`.

Current development baseline:

- Fedora Linux 43 KDE Plasma Desktop Edition
- Plasma Desktop 6.6.5
- NetworkManager 1.54 with systemd-resolved 258
- SDDM 0.21
- TuneD 2.27 with the `powersave` profile

## Prerequisites

- Physical access to the device
- A tested parent administrator account
- A separate child account, or a chosen name for one
- A current backup of files that cannot be replaced
- Internet access for package installation

Do not enable automatic login until the child account is confirmed to be
unprivileged. Do not remove desktop controls until parent recovery works.

## Audit

1. Run `bash scripts/fedora/audit.sh` on the Fedora machine.
2. Review the output for Fedora version, Plasma major version, display manager,
   NetworkManager, resolver, power service, and touchpad support.
3. Confirm that the versions match the supported development baseline.

## Child account

Create the dedicated account only after confirming the parent account has
working administrator access:

```bash
sudo bash scripts/fedora/create-child-user.sh chalkboard
```

The command is idempotent. It creates `/home/chalkboard`, locks password login,
and removes the account from `wheel` or `sudo` if present. It does not enable
automatic login or apply desktop restrictions. Preview it with `--dry-run`:

```bash
sudo bash scripts/fedora/create-child-user.sh --dry-run chalkboard
```

The audit is read-only. Deployment is split into independently verifiable phases
so that immutable policy is not applied before Plasma has generated its layout.

## Current policy decisions

- The dedicated child account is `chalkboard` and remains unprivileged.
- SDDM automatically logs into `chalkboard` once after boot.
- Power-button and detected lid-close events request a clean poweroff.
- Suspend and hibernation are disabled system-wide.
- The parent account and its Plasma configuration remain unrestricted.
- Parent recovery uses SSH or a local text console.

See the [deployment runbook](../deployment.md) and
[recovery guide](../recovery.md).

## Baseline corrections

- Fedora uses `dnf`, not the handoff's Kubuntu-specific `apt` instructions.
- Fedora KDE may use Plasma 6, whose commands and configuration differ from
  Plasma 5 examples such as `kwriteconfig5`.
- NetworkManager link DNS can coexist with systemd-resolved global DNS; writing
  only `resolved.conf` is not sufficient verification.
- Disabling the application launcher is not the same as disabling every shortcut
  that uses the Super/Meta key.
- ScratchJr should not be listed as a web app until the
  [publisher, maintenance, and browser verification criteria](../scratchjr-web-research.md)
  are all satisfied.
