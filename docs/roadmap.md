# Roadmap

## Next candidates

- Optional weather widget with an explicit location, provider, and privacy review
- Scheduled device downtime and per-application allowances
- Parent-activated single-application mode for younger children
- Owned-media Lutris and Wine profiles for compatible retro games
- Evaluation of community 3D Movie Maker ports and required original assets

## Design notes

NextDNS is an opt-in alternative resolver backend, not installed alongside the
default Cloudflare policy. Its configuration identifier remains deployment-
specific and must not be committed. Query logging requires an explicit family
privacy decision.

Parent access remains a separate account, SSH, and local console rather than
secret keyboard shortcuts inside the child session. The child retains
`Super+E` for file-management literacy, while direct KRunner and terminal
shortcuts remain hidden.

Retro-game automation will support only lawfully owned media. It will not ship
game data, cracked executables, or instructions whose purpose is bypassing copy
protection.
