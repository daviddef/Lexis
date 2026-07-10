# LEXIS — App Store submission checklist

## Screenshots (required)
Apple requires **iPhone 6.9"** (1320 × 2868) — App Store Connect derives smaller
iPhone sizes from it. Add **iPad 13"** (2064 × 2752) too, since LEXIS is universal.

Capture on a real device (Volume-Up + Side button) or the **iPhone 16 Pro Max**
simulator (6.9"). Suggested 6-shot set, in order, each with a short caption:

| # | Screen | Caption |
|---|--------|---------|
| 1 | Menu (LEXIS logo, modes) | "One letter. One word. One life." |
| 2 | Mid-game with a word glowing gold | "Words read 8 ways — even diagonally" |
| 3 | A big combo / clear-burst firing | "Chain words for huge combos" |
| 4 | Daily Challenge / Weekly event card | "A fresh puzzle every day" |
| 5 | Collection (themes + bursts + backdrops) | "Collect themes, bursts & backdrops" |
| 6 | Game Over with a high score | "Chase your best" |

Tip: turn on a nice tile **theme** and **backdrop** before shooting 2–3.

## Store metadata
- [ ] Name, subtitle, promo text, keywords, description → from `app-store-listing.md`
- [ ] Primary/secondary category: Word / Puzzle
- [ ] Age rating questionnaire → 4+
- [ ] Marketing URL, Support URL, Privacy Policy URL → deployed `docs/` on `daviddef.github.io/Lexis/`
- [ ] Privacy nutrition label (Game Center only for this ad-free 1.0)
- [ ] App icon (already in the asset catalogue)

## Build & technical
- [ ] Version reads **1.0** (project.yml) — note: App Store Connect may reject an
      upload below the 2.0 prerelease builds already there; clear those or ship
      as 2.0 if it won't take 1.0.
- [x] Export compliance declared (`ITSAppUsesNonExemptEncryption: NO`)
- [x] Launch screen, portrait-only, universal
- [ ] iCloud capability enabled on the App ID (CloudSync entitlement is in the
      build; the device archive needs the capability — usually auto via
      `-allowProvisioningUpdates`)
- [ ] Game Center: pre-create the leaderboards & achievements in App Store
      Connect (per-difficulty, daily, `lexis_leaderboard_weekly`, and the 7
      achievements) so scores/achievements post instead of silently no-oping

## Later (post-1.0, not blocking)
- [ ] AdMob SDK behind `RewardedAdProvider` + ATT prompt → then update the
      privacy label with advertising disclosures
- [ ] Analytics vendor (TelemetryDeck) one-line attach in `attachDefaultSinks()`
- [ ] Deploy `docs/` (marketing + privacy + app-ads.txt) to `daviddef.github.io/Lexis/`
