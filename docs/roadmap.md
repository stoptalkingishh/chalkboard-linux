# Roadmap

## Next candidates

- Additional keyless weather providers beyond the optional NOAA implementation
- Per-application daily allowances for the existing screen-time framework
- Hardware testing of the optional owned-media Wine framework
- Evaluation of community 3D Movie Maker ports and required original assets

## Design notes

NextDNS is a shipped alternative resolver backend, not a future plan and not a
second resolver installed alongside Cloudflare. `configure-dns.sh` writes one
systemd-resolved drop-in, so a backend switch replaces the previous one. The
configuration identifier remains deployment-specific and is stored only in
`/etc/chalkboard/nextdns-profile`; it is never committed. Query logging remains
an explicit family privacy decision for the parent.

Scheduled device downtime and the optional single-application GCompris session
are also implemented. `scripts/fedora/screen-time.py` enforces recurring
downtime for the child account, and `scripts/fedora/gcompris-mode.sh` provides
the parent-activated Cage session. Both are opt-in and disabled by default. See
[screen time](screen-time.md) and the
[deployment runbook](deployment.md#optional-single-app-gcompris-mode).

Per-application daily allowances are the one real screen-time remainder. The
framework accounts downtime for the whole account and does not count
per-application usage, as [screen time](screen-time.md) states.

Parent access remains a separate account, SSH, and local console rather than
secret keyboard shortcuts inside the child session. The child retains
`Super+E` for file-management literacy, while direct KRunner and terminal
shortcuts remain hidden.

Retro-game automation supports only lawfully owned media. It does not ship
game data, cracked executables, or instructions whose purpose is bypassing copy
protection.
