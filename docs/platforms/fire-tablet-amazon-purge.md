# Amazon package purge review

**Device:** Fire HD 8 10th generation / `KFONWI` / `onyx`  
**Fire OS:** 7.0 / Android 9 / `PS7331.4494N`  
**Profile reviewed:** Kids profile 11  
**Status:** Review only; no packages removed by this document.

## Review-first packages

These are the most likely sources of Amazon registration prompts, store surfaces, sponsored recommendations, or Amazon content. They require individual testing and a rollback plan:

- `com.amazon.kindle.otter.oobe` — Fire registration/setup activity
- `com.amazon.venezia` — Amazon Appstore
- `com.amazon.identity.auth.device.authorization` — Amazon account authentication
- `com.amazon.kindle.kso` — Kindle/Amazon promotional surfaces
- `com.amazon.firespotlight` — Fire content recommendations
- `com.amazon.windowshop` — Amazon shopping/content surface
- `com.amazon.advertisingidsettings` — advertising ID controls
- `com.amazon.sneakpeek` — preview/recommendation surface
- `com.amazon.weather` — Amazon weather surface
- `com.amazon.photos` — Amazon Photos integration
- `com.audible.application.kindle` — Audible integration
- `com.amazon.imdb.tv.mobile.app` — IMDb integration

## Keep until replacement is proven

Do not disable these as part of a first-pass purge:

- `com.amazon.parentalcontrols`
- `com.amazon.comms.kids`
- `com.amazon.cloud9.kids`
- `com.amazon.device.settings`
- `com.amazon.settings`
- `com.amazon.firelauncher` — recovery/default launcher; protected on this build
- `com.amazon.kindle.rdmdeviceadmin`
- `com.amazon.device.software.ota`
- `com.amazon.kindle.otter.oobe.forced.ota`
- `com.amazon.identity.auth.device.authorization` until registration behavior is resolved
- `com.android.systemui`
- `com.android.settings`
- Android package installer and providers

## Safe cleanup order

1. Back up package state and user/profile state.
2. Block or mute promotional notifications first.
3. Test private DNS/ad blocking without disabling system packages.
4. Disable one non-critical Amazon content package at a time.
5. Reboot and test Home, lock screen, profile switching, Appstore, and the approved apps.
6. Keep a written revert command for every change.
7. Do not remove protected packages, boot-chain components, OTA components, profile services, or recovery launchers.

## Why this is not an uninstall list

Fire OS rejected attempts to disable both `com.amazon.kindle.otter.oobe` and `com.amazon.firelauncher` because they are protected packages. A blind purge can break registration, profile switching, recovery, or the Home action. The preferred first implementation is a reversible no-root helper that can record and revert its own changes.

