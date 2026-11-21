# Fire HD 8 (10th gen) field inventory

This document records a read-only inventory from a Fire HD 8 (2020, 10th generation; model `KFONWI`) to guide future Chalkboard Fire-tablet support.

## Device scope

- Platform: Fire OS 7 / Android 9 (API 28)
- Build display ID: `PS7331.4494N`
- Captured by: ADB package and usage-stat inspection
- Purpose: document a real family-device workload before implementing optional ADB helpers
- Safety: no packages were disabled, removed, or modified during collection

The repository does not include the tablet serial number, account information, raw usage logs, or APK binaries.

## Installed user packages

The following 37 third-party packages were present:

### Learning and creative

- `com.duolingo.literacy`
- `org.scratchjr.android`
- `org.khankids.android`
- `com.internetdesignzone.kidlolandcoding`
- `com.sesameworkshop.familyplaycaring.amazon`
- `org.pbskids.gamesapp`
- `org.pbskids.video`
- `com.MusterenGames.AlgorithmCityTheSnowCoder`
- `com.axis.drawingdesk.v3`

### Games

- `com.agedstudio.amazon.wood.block.puzzle.sudoku.game`
- `com.amelosinteractive.snakeamazon`
- `air.com.hypah.kindle.io.slither`
- `com.netflix.NGP.BloonsTDSix`
- `com.netflix.NGP.BowlingBallers`
- `com.netflix.NGP.CutTheRopeDaily`
- `com.netflix.NGP.KrispeeStreet`
- `com.netflix.NGP.Mahjong`
- `com.netflix.NGP.Minesweeper`
- `com.netflix.NGP.PuzzleGods`
- `com.netflix.NGP.ShatterRemastered`
- `com.netflix.NGP.ShootingHoops`
- `com.netflix.NGP.Snakeio`
- `com.netflix.NGP.SonicDash`
- `com.netflix.NGP.SpongeBobKrustyCookOff`
- `com.netflix.NGP.WorldofGooHD`
- `com.budgestudios.amazon.PawPatrolRescueWorld`
- `com.storytoys.myveryhungrycaterpillar.free.android.amazon`
- `com.storytoys.hungry.caterpillar.play.school.abc.kids.books.free.android.googleplay`

### Video, music, and media

- `com.google.android.youtube`
- `com.netflix.mediaclient`
- `com.hulu.plus`
- `com.peacock.peacockfiretv`
- `com.hbo.hbonow`
- `com.apple.android.music`
- `org.jellyfin.mobile`

### Platform support installed as user packages

- `com.android.vending`
- `com.google.android.gms`
- `com.google.android.gsf`
- `com.google.android.gsf.login`

## Likely children’s favorites

The usage-stat database contains long-lived cumulative counters, including stale entries and background/media activity, so exact durations are not treated as a reliable ranking. The strongest candidates to confirm with the family are:

1. Wood Block Puzzle / Sudoku
2. ScratchJr
3. Duolingo ABC / literacy
4. Netflix games: Snake.io, Shooting Hoops, Bowling Ballers, World of Goo, Krispee Street, Sonic Dash, and SpongeBob Krusty Cook-Off
5. PBS Kids Games and PBS Kids Video
6. Khan Academy Kids
7. Paw Patrol Rescue World
8. The Very Hungry Caterpillar titles
9. Algorithm City: The Snow Coder
10. KidloLand Coding

This list should become an explicit parent-approved catalog rather than an automatic allowlist. Usage statistics alone should not decide what is permitted for a child account.

## Backup notes

A local ADB backup was created while collecting this inventory. Package manifests and raw usage data remain local. Some APK splits could not be pulled because Fire OS placed them under protected adopted-storage paths; this is expected on a non-rooted Fire OS device and does not affect the inventory.

## Follow-up

- Confirm the favorite-app list with the parent before implementing a Chalkboard catalog.
- Design ADB helpers around read-only audit, explicit package selection, and reversible changes.
- Test package visibility and launcher behavior on a clean child profile before considering any disable/restore workflow.
