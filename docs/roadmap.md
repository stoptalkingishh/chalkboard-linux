# Roadmap

## Next candidates

- Additional keyless weather providers beyond the optional NOAA implementation
- Configurable NextDNS backend as an alternative to Cloudflare Families
- Scheduled device downtime and per-application allowances
- Parent-activated single-application mode for younger children
- Owned-media Lutris and Wine profiles for compatible retro games
- Evaluation of community 3D Movie Maker ports and required original assets

## Design notes

NextDNS should be an alternative resolver backend, not installed alongside the
current Cloudflare policy. Its profile identifier is deployment-specific and
must not be committed. Query logging also requires an explicit family privacy
decision.

Parent access remains a separate account, SSH, and local console rather than
secret keyboard shortcuts inside the child session. The child retains
`Super+E` for file-management literacy, while direct KRunner and terminal
shortcuts remain hidden.

Retro-game automation will support only lawfully owned media. It will not ship
game data, cracked executables, or instructions whose purpose is bypassing copy
protection.
