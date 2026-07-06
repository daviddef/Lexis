# LEXIS — Setup Notes

## Adding the dictionary resource file

The word validator (`WordValidator` in `GameModel.swift`) now loads a real
dictionary from `Resources/lexis_dictionary.txt` at launch, instead of a
small hand-typed word list. This fixes real gaps in word coverage — for
example "RAVE" was previously missing despite being a common word, which
broke the game's core "yellow glow = valid word" promise.

The list is derived from **ENABLE1**, a well-established, freely
redistributable general-English word list commonly used in word games
(Scrabble clones, Words With Friends-style apps, etc.). It's filtered to
3–9 letter words (~105,000 entries, ~850KB) to match this game's realistic
board dimensions and `minWordLength` setting.

### To add it to your Xcode project:

1. Drag `Resources/lexis_dictionary.txt` into your Xcode project navigator
   (anywhere under the app target is fine — a `Resources` group is tidy).
2. When prompted, make sure **"Copy items if needed"** is checked and the
   file is added to your app's target under **Target Membership**.
3. Verify it shows up under your target's **Build Phases → Copy Bundle
   Resources**. If it's missing from that list, the app will fall back to
   a tiny 14-word emergency list and fire an `assertionFailure` in debug
   builds — that's a deliberate safety net, not silent failure, so you'll
   know immediately if the resource didn't get bundled correctly.

### If you want to customize the dictionary

- To exclude offensive terms: ENABLE1 is intentionally a fairly clean
  general list already, but if you want to scrub further, edit
  `Resources/lexis_dictionary.txt` directly (one word per line, lowercase)
  before adding it to Xcode.
- To adjust word length range: the current file is pre-filtered to 3–9
  letters. If you change `GameConstants.minWordLength` or want longer
  words playable, regenerate the file from the full ENABLE1 source
  (https://raw.githubusercontent.com/rressler/data_raw_courses/main/enable1_words.txt)
  with your own length filter.

## Note on the browser preview (LEXIS_Preview.jsx)

The React preview can't read arbitrary local files at runtime, so it uses
a smaller inline word list (~13,500 words, 3–5 letters) rather than the
full dictionary the Swift app bundles. It's still dramatically more
complete than the original hand-picked list and correctly includes common
words like "rave" — but for full-scale testing of word coverage, the
actual iOS app is the source of truth.

## Daily Challenge mode

`DailyChallengeManager.swift` adds a Wordle-style daily mode: every player
gets an identical 40-letter sequence each calendar day, generated from a
deterministic seed (hashed from the date string), so results are directly
comparable worldwide. One attempt per day, streak tracking, and a
Wordle-style emoji share card (no board spoilers — just score tier, word
count, and longest word).

Key design choices:
- **Fixed drop speed** (not the escalating difficulty curve) — the daily
  challenge tests optimal word-finding against a shared fixed letter set,
  not reflexes against increasing speed.
- **No wildcards or bombs** — again, fairness: every player's 40 letters
  are identical, so power-ups that could vary the experience are removed.
- **Separate high-score tracking** from endless/difficulty-tier modes,
  since it's a fundamentally different kind of challenge.
- Uses a hand-rolled splitmix64-style PRNG rather than Swift's built-in
  `RandomNumberGenerator`, because Swift's generator isn't guaranteed
  reproducible across OS versions — the daily puzzle needs to be stable
  forever, not just "consistent for now."

## The Tip mechanic

A limited-use action that lets players reach into a settled stack and
knock its topmost tile sideways onto a neighboring column, purely to
reveal whatever word might be readable underneath. Unlike the "clear
path" bomb, tipping doesn't destroy a tile — it's conserved and re-enters
play at the top of the neighboring stack, so it's a tactical trade
(reshuffle for a shot at a word) rather than a free escape valve.

- **Earned from chained combos** (every 3rd combo step), distinct from
  bombs which reward long words — so the two currencies reward different
  kinds of skill (tempo/reading ahead vs. vocabulary).
- **Two-step interaction**: tap the violet-ringed top tile of any column
  to arm it, then choose left or right from the picker that appears.
  Tapping the same tile again cancels the selection.
- **Excluded from Daily Challenge** for the same fairness reason as
  wildcards and bombs — every player faces an identical 40-letter
  sequence with no variable power-ups.
- Only the single topmost tile of a column is ever eligible, and a
  destination column that's already full to the ceiling is a blocked
  target, same as normal movement collision rules.

## Recent fixes (this iteration)

- **Wildcard picker is now a floating overlay, not inline layout.** A
  small pulsing star badge appears over the top-right of the board and
  auto-expands into a compact 5-letter popover — it no longer eats
  vertical space from the control stack the way the old full-width
  12-letter grid did.
- **Wildcard letters are now smart-picked**, not a fixed list. The 5
  candidates favor letters absent from the current board (or with the
  lowest count on it), from a pool of generally useful letters — so the
  wildcard actually helps unblock a stuck board rather than repeating
  whatever's already plentiful.
- **Longer word always wins over a contained shorter word.** If a run
  contains both a valid short word and a valid longer word that fully
  contains it (e.g. "END" inside "REVEREND"), only the longer word is
  offered for clearing — the shorter one is suppressed, not offered
  alongside it.
- **Fixed a real gesture-recognition bug** where the Tip mechanic's
  single-tap-to-select and the word-clear double-tap were two independent
  `.onTapGesture` modifiers on the same tile view. SwiftUI's tap-count
  recognizers can race each other in that pattern, causing single taps to
  silently fail to register — which read as "knocking behaves like the
  sticky mechanic" even though sticking and Tip are architecturally
  unrelated systems. Fixed with a single gesture using
  `.exclusively(before:)` so the double-tap recognizer gets first refusal
  and only falls through to single-tap after its window expires.
