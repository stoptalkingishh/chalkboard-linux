# Fire tablet research and setup log

**Date:** 2026-11-21  
**Device:** Amazon Fire HD 8 (10th generation, 2020)  
**Model:** KFONWI  
**Codename:** `onyx`  
**Fire OS:** 7.0  
**Android API:** 28 / Android 9  
**Build:** `PS7331.4494N`  
**Build fingerprint/incremental supplied by owner:** `0031575871108`

This document records the current Fire tablet work for Chalkboard. It is a research and decision record, not a claim that the tablet is ready for a stable child deployment.

## Goal

Create a family-owned tablet experience that:

- looks and behaves similarly to the family iPad layout;
- keeps the adult account available for maintenance;
- gives children only approved games and learning apps;
- blocks purchases, app installation, stores, browsers, and settings access from the child-facing experience;
- avoids ads, sponsored recommendations, and Amazon registration prompts;
- remains recoverable and understandable by the parent.

## Current device users

| User ID | Name | Role/status |
| --- | --- | --- |
| 0 | Gabby Rodriguez | Adult/admin profile; registered Amazon device account |
| 10 | Eliana | Native Amazon Kids profile |
| 11 | Kids | Existing secondary Kids profile used for experiments |
| 12 | Kids Clean | Temporary clean Android-user test profile created during this work |

Profile 12 was intentionally created as a non-destructive test. It should not be treated as the production child profile.

## Apps and layout work completed

The following approved apps were made available to the adult profile from APKs already present on the tablet or in the local backup:

- PBS KIDS Games
- PBS KIDS Video
- Duo ABC
- GCompris
- Khan Kids
- Bluey: Let’s Play! by Budge Studios
- Kiddopia
- Prodigy
- ABC Kids
- Coloring Games
- Coloring Club
- Paint
- My Very Hungry Caterpillar
- Play School / Caterpillar-related app
- Sesame Play
- The Snow Code / Algorithm City
- BlockPuzzle
- Jellyfin

The existing Kids profile also contained these apps. The Bluey package was verified as:

`com.budgestudios.amazon.BlueyBLU`

The iPad screenshots identified additional desired apps, including Baby Piano. Baby Piano was not found installed on the tablet, in the local APK backup, or in the package list for the Kids profile.

Initial-screen ad inspection was performed on the installed kid apps. No visible ad labels or ad prompts appeared on the first screen of the inspected apps. This is not proof that an app cannot show ads later.

## Launcher experiments

### Supernova

Supernova was installed and used to create an iPad-like grid. It successfully showed kid apps such as PBS KIDS, Duo ABC, GCompris, Khan Kids, Hungry Caterpillar, Paint, Bluey, BlockPuzzle, Coloring apps, ABC Kids, Kiddopia, and Prodigy.

Problems:

- its search surface was difficult to remove consistently;
- pinned icons and drawer state were inconsistent after restart;
- Fire OS continued to reclaim or overlay Amazon launcher behavior;
- Amazon’s launcher remained protected and could not be disabled with normal ADB;
- the adult profile’s Home action eventually returned to Amazon’s launcher and its sponsored content.

Supernova remains useful for experiments but is not yet a proven production launcher on this Fire OS build.

### Nova

Nova was installed briefly. It displayed advertising content, so it was removed from the Kids profile. It is not an approved Chalkboard default.

### Amazon launcher

`com.amazon.firelauncher` is protected on this build. Attempts to disable it with:

```text
pm disable-user --user 0 com.amazon.firelauncher
```

were rejected by Fire OS with a protected-package security exception.

The protected registration component is:

`com.amazon.kindle.otter.oobe`

Attempts to force-stop or disable it were also rejected. ADB can clear its task temporarily and reopen the launcher, but that does not remove the underlying condition.

## Profile experiments

### Clean Android user 12

A clean Android user was created to test whether a fresh profile would avoid the existing Kids-profile state.

Result: it immediately launched Amazon's protected registration activity:

`com.amazon.oobe.registration.RegistrationActivity`

The screen asked for an Amazon email/mobile number and password. This demonstrates that creating a normal Android user does not avoid Amazon registration on this Fire OS build.

### Native Amazon Kids profile 10

The native Kids profile eventually loaded its Amazon Kids+ interface. It had strong child-oriented restrictions, but the home screen included:

- Amazon Kids+ branding;
- Discover / Watch / Listen / Read / Play / Learn sections;
- subscription status;
- store and web browser surfaces;
- Amazon recommendation content;
- sponsored or Amazon-managed content rows.

This profile is the most stock-stable child mode, but it does not meet the desired clean iPad-like interface.

### Existing Kids profile 11

Profile 11 was used for app and launcher experiments. It contains the child apps, but also inherits Fire OS protected services and the same registration/profile-switching complications. It should not be deleted until a final replacement strategy is chosen.

## User switching findings

The system reports the user switcher enabled and no `no_switch_user` restriction. However, the Kids interface does not reliably expose the Quick Settings profile switcher.

The reliable on-device path observed was:

1. Lock the tablet.
2. Wake the lock screen.
3. Tap the profile icon in the top-right corner.
4. Select the adult profile.
5. Enter the parent PIN if requested.

The Settings > Multiple users page shows the profiles but functions primarily as profile management; it is not a reliable account-switch action on this Fire OS build.

## Google Play and store findings

Google Play components were repaired for the adult profile using APKs already present on the tablet:

- Google Account Manager
- Google Services Framework
- Google Play services
- Google Play Store

The Play Store stopped crashing after the repair, but store requests still produced a server error. App-store search was not a dependable installation path during this work.

Amazon Appstore was present but became stuck on a loading screen during testing.

The preferred future installation workflow is therefore:

1. obtain a trusted APK or split APK;
2. verify its package name and checksum;
3. install with ADB;
4. test on Android 9 / Fire OS 7;
5. make it available only in the intended profile;
6. record the result here or in an app manifest.

## Research findings

### Full custom OS / LineageOS

An unofficial LineageOS 18.1 release exists for the Fire HD 8 / HD 8 Plus 10th generation (`onyx`). The release is marked beta and requires a bootloader unlock and custom recovery.

This is the only route that can genuinely replace Fire OS and remove Amazon's launcher and protected services, but it is also the highest-risk route.

Open questions before considering it:

- Is the bootloader unlock path still valid for this exact build?
- Does the release support Wi-Fi, audio, camera, GPU acceleration, sleep, and the touchscreen reliably?
- Is recovery/rollback documented for this exact hardware revision?
- Does the tablet have a verified offline backup?
- Can the parent recover the device if flashing fails?

Do not flash the Lineage image until those questions are answered and the correct device-specific instructions are verified.

### Bootloader and temporary-root research

Community reports identify `PS7331/4494` as a significant Fire OS 7 build family. Reports also warn that newer updates may patch temporary-root or bootloader-unlock paths. These reports are community research and should not be treated as a guaranteed exploit or supported installation method.

Do not:

- downgrade using an image that is not verified for `onyx`;
- flash a bootloader, preloader, recovery, or vendor image from another Fire model;
- run generic MediaTek flashing tools against this tablet;
- attempt a bootloader unlock without a complete recovery plan.

### No-root Fire OS cleanup

An open-source ADB-only project named **embertools** advertises:

- a launcher-swap helper for Fire OS 7;
- reversible debloating;
- ad and tracker blocking;
- OTA blocking;
- private DNS configuration;
- state tracking and revert support.

Its documentation says it was tested on a different Fire OS 7 device and lists the Fire HD 8 2020 as a device needing testing. It is promising but not yet validated for `onyx` / `PS7331.4494N`.

This is the preferred next experiment because it does not require flashing or bootloader changes, but it must be tested with backups and one reversible module at a time.

## Decision matrix

| Option | iPad-like UI | Removes Amazon prompts | Child restrictions | Risk | Recommendation |
| --- | --- | --- | --- | --- | --- |
| Native Amazon Kids | No | No | Strong | Low | Stable fallback only |
| Supernova/Nova on stock Fire OS | Partial | No | Weak unless separately managed | Low-medium | Experiment only |
| Adult profile + no-root cleanup | Yes, potentially | Mostly | Parent-managed, not true profile isolation | Medium | Best near-term path |
| embertools-style ADB helper | Yes, potentially | Potentially | Parent-managed | Medium | Validate carefully |
| LineageOS/custom ROM | Yes | Yes | Must be rebuilt | High | Research only until unlock is proven |
| Random APK/ROM flashing | Unknown | Unknown | Unknown | Very high | Do not use |

## Proposed next steps

1. Keep profiles 0, 10, 11, and test profile 12 intact until the architecture is selected.
2. Create an offline backup and record package state before further changes.
3. Freeze OTA updates only after reviewing the implications for security and recovery.
4. Validate embertools support and source integrity for `KFONWI / onyx / PS7331.4494N`.
5. Test only the launcher-swap module first.
6. Reboot and test Home, lock screen, profile switching, and recovery.
7. Test debloating in small batches, keeping Amazon profile, settings, OTA, and recovery components.
8. Build a fixed child-facing app manifest, including a decision for Baby Piano.
9. Only after the no-root path is stable, revisit LineageOS and bootloader research.

## Safety boundaries

- Do not commit credentials, Amazon account data, device serial numbers, or private APKs.
- Do not delete profile 10, 11, or 12 until the final strategy is proven.
- Do not disable protected Fire OS components blindly.
- Every device change should have a rollback command or a documented factory-recovery path.
- Apps for children should be checked for purchases, ads, external links, login requirements, and network behavior.
- The adult profile must retain a tested recovery path before the child-facing UI is locked down.

## References

- Amazon Fire tablet software updates: https://digprjsurvey.amazon.com/csad/help/node/G2JXLC4L34GX73TE?theme=light
- LineageOS 18.1 onyx release listing: https://github.com/amazon-oss/releases/releases
- embertools repository and documentation: https://github.com/BlueMonkey262/embertools
- Fire HD 8 10th-gen / onyx unlock research issue: https://github.com/bkerler/mtkclient/issues/162
- Fire OS 7 / onyx community exploit warning: https://www.reddit.com/r/AmazonFire/comments/1y0gjbz/important_notice_regarding_bootloader_unlocking/
- Background on older Fire HD custom ROM support and the 10th-gen limitation: https://liliputing.com/run-android-10-on-the-2018-amazon-fire-hd-8-tablet-unofficially-with-lineageos-17-1/
