# LEXIS — App Store submission checklist

**Shipping as version 2.1** (2.0 is already approved/locked on App Store
Connect). This build serves **live rewarded AdMob ads**, which drives several
items below (privacy label, ATT). Latest TestFlight build: 2.1 (build 1) — note
the power-up-panel fix and screenshot harness landed *after* it, so **cut a new
build before submitting**.

## Screenshots (required)
Apple requires **iPhone 6.9″** (1320 × 2868). Captured set lives in
`store/screenshots/` (see its README for captions).

- [x] `01-menu.png` — menu / modes
- [x] `02-gameplay.png` — ocean scene, words glowing (the 8-way hook)
- [x] `03-gameover.png` — new top score
- [ ] *(optional)* Collection + combo/burst shots for a fuller listing
- [x] **iPad 13″** set (required — universal) → `store/screenshots/ipad/`

## Store metadata
- [ ] Name, subtitle, promo text, keywords, description → from `app-store-listing.md`
- [ ] Primary/secondary category: Word / Puzzle
- [ ] Age rating questionnaire → 4+
- [x] Marketing / Support / Privacy Policy URLs → live at `https://daviddef.github.io/Lexis/`
- [ ] **Privacy nutrition label — ads are LIVE**, so declare **Third-Party
      Advertising + Device ID (IDFA), Used to Track You**, plus Game Center.
      (Was "Game Center only" — no longer true.)
- [x] App icon (in the asset catalogue)

## Build & technical
- [x] Version 2.1 (project.yml); 2.0 is locked
- [x] Export compliance declared (`ITSAppUsesNonExemptEncryption: NO`)
- [x] Launch screen, portrait-only
- [x] AdMob live: real App ID + rewarded unit, UMP consent + ATT, `app-ads.txt`
      live at the marketing URL
- [ ] **Real-device Release pass (Guideline 2.1)** — crash-free with the ad SDK
      running at launch; confirm the rewarded video actually plays (proves the
      unit is Rewarded, not Native), notifications, Game Center, iCloud, haptics
- [ ] iCloud capability on the App ID (usually auto via `-allowProvisioningUpdates`)
- [ ] **Game Center** — tick the checkbox on the version, then create the 6
      leaderboards + 7 achievements and upload the 13 icons.
      Everything is in `store/game-center-setup.md` + `store/gamecenter-icons/`.

## Device support — universal (forced)
- [x] **Universal, iPhone + iPad** (`TARGETED_DEVICE_FAMILY: "1,2"`). iPhone-only
      is NOT possible: 2.0 shipped universal, and Apple's QA1623 rejects an
      update that drops a device family ("This bundle does not support one or
      more of the devices supported by the previous app version"). Verified the
      iPad board is acceptable (centered, full-height, aligned).
- [x] **iPad 13″ screenshots** — in `store/screenshots/ipad/` (required now that
      iPad support is locked in).

## Known gap (not a hard blocker, but you're launching blind)
- [ ] **No analytics vendor attached** — `Analytics.attachDefaultSinks()` is
      console-only. Without it there's no D1/D7 retention or funnel data to tune
      the whole retention system against. One-line attach once a vendor
      (e.g. TelemetryDeck) is set up.
