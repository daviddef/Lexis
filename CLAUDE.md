# CLAUDE.md — Context for Claude Code

This file exists so a Claude Code session can pick up this project instantly
without re-deriving decisions that have already been made and validated.
Read this before making changes.

## What this is

**LEXIS** — an iOS word-puzzle game, SwiftUI, built from scratch. The core
pitch: a single lettered tile falls (Tetris-style), the player steers it,
and instead of clearing rows you're forming words that can read in any of
8 directions (horizontal, vertical, both diagonals, each forwards and
backwards). Formed words glow yellow and pulse; a double-tap confirms the
clear. The board fills up and you lose if you can't keep pace.

This was deliberately researched against every existing game in the
space (SpellTower, Typeshift, Letris, Letterfall, WordDrop, Droplett) to
confirm it isn't a clone. The differentiators that make it genuinely new:

1. **Player-directed column placement** (like classic Tetris) — most
   word-Tetris games give you no control over where letters land.
2. **Directional word detection with a deliberate asymmetry**: horizontal
   reads left-to-right only (no backwards spelling), vertical reads work
   both top-to-bottom and bottom-to-top, and diagonals are forward-only.
   This was a deliberate design choice for readability/predictability, not
   an oversight — don't "fix" it back to all-8-directions.
3. **Side-sticking** — a falling letter can catch the side of an existing
   tower and cling there instead of only stacking straight down, letting
   players build words at height, not just vertically.
4. **The Tip mechanic** — a limited-charge action to knock the topmost
   tile of a column sideways onto a neighbor, purely to reveal a word
   underneath. The tile is conserved (relocated, not destroyed), so it's
   a tactical trade, not a free escape.
5. **Glow-then-confirm** word clearing (yellow pulse + double-tap) rather
   than instant auto-clear, so finding a word feels like a deliberate,
   satisfying action.

## Current status: builds and runs (Xcode project generated via xcodegen)

`LEXIS.xcodeproj` exists and is committed. It's generated from
`project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`xcodegen generate`) rather than hand-authored or created through the
Xcode "New Project" wizard -- `.xcodeproj` internals are largely
binary-plist state that's risky to hand-roll, and XcodeGen gives a
deterministic, diffable, regeneratable project from a small YAML spec
instead. **If you need to change target settings, sources, bundle ID,
entitlements, etc., edit `project.yml` and re-run `xcodegen generate` --
don't hand-edit `project.pbxproj`.**

Key settings baked into `project.yml`: bundle ID
`com.daviddefranceski.lexis`, team `L9SAXP2E2W` (matches this developer's
other iOS projects), iOS 17 deployment target, universal (iPhone+iPad,
matching the bundled iPad icon sizes), Game Center entitlement, and
`INFOPLIST_KEY_UILaunchScreen_Generation = YES` (the plain
icon-on-background-color system launch screen -- see "Not yet built"
below for the alternative custom-storyboard approach).

**To build after cloning:**
```
xcodegen generate   # only needed if project.yml changed since last generate
xcodebuild -project LEXIS.xcodeproj -scheme LEXIS -destination 'generic/platform=iOS Simulator' build
```
or just open `LEXIS.xcodeproj` in Xcode and run.

### Two real bugs found and fixed when this was built and run for the first time

This source had never actually been compiled or run before a
`.xcodeproj` existed -- so beyond the setup step itself, getting it
building surfaced two genuine bugs in the original source, not just
config work:

1. **Swift type-checker timeout in `GameView.swift`.** `PlayingView.body`
   was a single ~500-line SwiftUI expression (header, status banner,
   board, recent-words strip, and the whole controls panel all inline in
   one `var body`), which the compiler couldn't type-check in reasonable
   time. Fixed by splitting it into separate computed properties
   (`headerBar`, `statusBanner`, `boardArea`, `recentWordsStrip`,
   `controlsPanel`) that `body` composes -- pure mechanical extraction,
   no behavior change. **If `body` properties grow large again, split
   them the same way rather than letting one giant expression regrow.**
2. **`WordResult` needs `Equatable`.** `.onChange(of: model.lastWordResult)`
   requires it and the type-checker timeout above had been masking this
   error entirely (compilation never got far enough to report it). Fixed
   by adding `Equatable` conformance to `WordResult` in `GameModel.swift`
   (synthesizes for free -- every stored property was already
   `Equatable`).
3. **Tile size was derived from screen width only**, ignoring height.
   With a 14-row board this overflowed every device's screen height,
   which SwiftUI resolved by rendering everything at natural size and
   letting the whole `PlayingView` VStack get center-clipped -- the
   header vanished off the top and most of the controls panel (drop
   button, bomb/tip UI) vanished off the bottom, while only the board and
   one row of the controls panel showed. Fixed in `GameView.swift`: the
   fixed `tileSize` property became a `GeometryReader`-driven
   `tileSize(for:)` function that constrains by both width AND a
   reserved-height budget for the non-board chrome, so the full layout
   fits on any device. **If you change `GameConstants.rows`/`cols` or add
   substantial new UI chrome to the controls panel, revisit the
   `reservedChromeHeight` constant in that function.**

## File map

| File | Responsibility |
|---|---|
| `LexisApp.swift` | App entry point; on launch runs `DataMigration`, Game Center auth, analytics, MetricKit, notification + goals + weekly + StoreKit setup |
| `GameModel.swift` | Core game engine: grid state, word detection (left-to-right horizontal only, both directions vertical), scoring, difficulty tiers, settings, sticking mechanic, Tip mechanic, soft-drop, haptics, the dictionary loader, top-scores leaderboard. Also the three fixed-sequence modes (Daily, Duel, Weekly) |
| `GameView.swift` | All SwiftUI views: menu/splash, playing board, tile rendering, game over, daily/duel/weekly result screens, share sheet, celebration toasts |
| `SettingsView.swift` | Settings screen + difficulty picker + notification controls |
| `DailyChallengeManager.swift` | Daily Challenge mode: date-seeded deterministic letter sequence, streaks, share card generation |
| `GameCenterManager.swift` | Game Center leaderboards (per-difficulty, daily, weekly) and achievements |
| `LaunchScreenView.swift` | Static launch-screen view (see Xcode setup step 8 for how this wires into the actual system launch screen) |
| `DesignSystem.swift` | Design tokens (spacing/radius), button styles, cards, pressable modifier |
| **Release 2.0 (retention & revenue) systems:** | |
| `Analytics.swift` | Vendor-agnostic telemetry: typed events + pluggable sinks (DEBUG console today; attach TelemetryDeck in `attachDefaultSinks()`). No PII |
| `MetricKitReporter.swift` | Apple-native crash/hang diagnostics → analytics, zero third-party SDK |
| `NotificationManager.swift` | Local notifications: daily reminder, streak-at-risk, win-back. Opt-in after first daily; idempotent `refresh()` |
| `Progression.swift` | `PlayerProfile` (XP/level/coins) + `GoalsManager` (3 date-seeded daily goals). The meta engine |
| `ProgressionView.swift` | Progress sheet, level chip, goal rows, `CollectionView`/`ThemeCard` shop UI, celebration toast |
| `CosmeticsStore.swift` | Owns theme ownership (milestone OR coin buy); one grant sink shared with StoreKit; milestone-unlock celebration |
| `WeeklyEventManager.swift` + `WeeklyEventViews.swift` | Weekly Challenge / Weekend Sprint event on the seeded-sequence engine + result screen |
| `AdManager.swift` | Network-agnostic **rewarded** ads (opt-in only; never interstitials). DEBUG stub makes the watch→reward flow testable with no SDK. Four placements: Endless boost, coins, on-demand charge (mid-run), revive. Needs an AdMob/AppLovin provider to serve real ads |
| `DataMigration.swift` | Schema-version stamp + ordered migration runner (run before any manager reads defaults) |
| `Assets.xcassets/AppIcon.appiconset` | Complete app icon set, all required sizes pre-rendered, matching the in-game tile's bevel/gradient look |
| `Resources/lexis_dictionary.txt` | ~105,000-word dictionary (ENABLE1-derived, 3-9 letters), loaded at runtime by `WordValidator` in `GameModel.swift` |

## Known constraints / decisions already made -- don't relitigate these

- **Dictionary is a bundled resource file, not an inline string.** An
  earlier version hardcoded ~1,900 words inline and had real gaps (e.g.
  "RAVE" was missing). Don't regress to an inline word list.
- **Daily Challenge deliberately excludes wildcards, bombs, and Tips.**
  Every player needs an identical experience for the mode's comparability
  promise to hold. Don't add power-ups to daily mode without reconsidering
  that tradeoff explicitly.
- **Tip charges are earned from combo chains; bomb charges from long
  words.** This is intentional -- two currencies rewarding different
  kinds of skill (tempo vs. vocabulary). Don't merge them into one
  currency.
- **Movement uses drag gestures + double-tap-to-drop, not on-screen
  arrow buttons.** An earlier version had arrow buttons; they were
  removed in favor of direct-manipulation touch controls per explicit
  design feedback.
- **Decorative overlay views must have `.allowsHitTesting(false)`.** A
  real bug occurred where an ambient grid-line overlay silently absorbed
  taps meant for buttons underneath it. If you add new decorative/ambient
  visual layers to the board, this is required, not optional.
- **Word direction rule is deliberately asymmetric, not "all 8
  directions."** Horizontal: left-to-right ONLY. Vertical: both
  directions count. Diagonals: forward-only (matching horizontal's "no
  backwards" rule). This was an explicit design change away from an
  earlier all-directions version — if you touch `findAllWords()` in
  `GameModel.swift`, preserve this asymmetry rather than "fixing" it back
  to symmetric.
- **Longer word wins over a shorter word it contains.** If a run has both
  a valid short word and a valid longer word that fully contains it (e.g.
  "END" inside "REVEREND"), only the longer word is offered for clearing.
  See `checkSubstrings()` in `GameModel.swift`.
- **Tap-gesture handling on tiles must use a single combined gesture, not
  multiple `.onTapGesture` modifiers with different counts.** A real bug
  occurred where independent `.onTapGesture(count: 1)` and
  `.onTapGesture(count: 2)` on the same view raced each other
  unreliably. Use `TapGesture(count:).exclusively(before:)` instead if
  you need to add another tap-count-dependent interaction to a tile.
- **Wildcard letter choices are computed, not a fixed list.** See
  `wildcardCandidates()` in `GameModel.swift` — it favors letters absent
  from or scarce on the current board. Don't hardcode the letter options
  back to a static array.

## Release 2.0 — needs YOUR setup before it fully works on-device

The 2.0 retention/revenue systems are code-complete and build clean, but a
few things require your Apple accounts / hardware (they degrade gracefully
until then — the app runs fine with none of these configured):

- **Monetization is ads-only (rewarded), NOT IAP.** The StoreKit shop was
  removed in favour of opt-in rewarded ads. To serve real ads: create an
  AdMob (or AppLovin) app + a *rewarded* ad unit, add the SDK as a Swift
  Package, implement `RewardedAdProvider` around it, add an App Tracking
  Transparency + consent prompt (changes the privacy nutrition label), and
  pass the provider to `AdManager.shared.configure(_:)` in `LexisApp`. Until
  then a DEBUG stub makes the watch→reward flow testable and release builds
  simply show no ads. Rewarded-only, never interstitials.
- **Weekly Game Center leaderboard** — create board id
  `lexis_leaderboard_weekly` in App Store Connect (submits no-op until then).
- **Analytics vendor** — recommend TelemetryDeck; attach in
  `Analytics.attachDefaultSinks()` (one line). Console-only in DEBUG today.
- **iCloud progress sync** — deliberately NOT wired (adding the iCloud KVS
  entitlement blindly can break device signing). `DataMigration` gives the
  versioning seam; add `NSUbiquitousKeyValueStore` mirroring once the iCloud
  capability is enabled on the App ID.
- **Real-device pass** — notifications, StoreKit, haptics, and Game Center
  all behave differently on device vs. Simulator; verify before shipping.
- **Notification copy** — draft strings live in `NotificationManager.swift`
  for your review/tuning before release.

## Not yet built (potential next steps, not committed to)

- Sound design / SFX  *(done — procedural `SoundManager`; layered in P05)*
- Custom `LaunchScreen.storyboard` matching `LaunchScreenView.swift`'s
  exact tile/wordmark, if the plain auto-generated icon-on-background
  launch screen (current setup) isn't good enough
- CI (GitHub Actions) for build verification on PRs -- straightforward
  now that the Xcode project exists (`xcodebuild ... build` as shown
  above)
- Board backdrops / clear-burst colour sets as additional cosmetic
  categories (R4 added themes only; `CosmeticsStore` is theme-scoped today)

## Browser preview

A standalone React/JSX version (not part of this repo's build target)
exists for quickly testing gameplay feel in a browser without opening
Xcode. It intentionally uses a smaller inline dictionary (~13,500 words,
3-5 letters) since browser artifacts can't read arbitrary local files at
runtime -- the real dictionary lives only in the Swift app. If you want
that file, ask; it wasn't included in this repo since it isn't part of
the shipped iOS app.
