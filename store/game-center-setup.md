# LEXIS — Game Center setup (App Store Connect)

The build already ships the Game Center entitlement (`project.yml` →
`com.apple.developer.game-center: true`). What remains is **App Store Connect
configuration only — no rebuild needed**:

1. On the app **version** page → tick the **Game Center** checkbox.
2. In the app's dedicated **Game Center** section, create the leaderboards +
   achievements below (the version page no longer lets you add them), then add
   them to the version for review.

**IDs must match character-for-character** (all lowercase, underscores) or the
code's report calls silently no-op. Verified against `GameCenterManager.swift`
+ `AchievementTracker` — the code references exactly these 13 IDs, nothing else.

Icons: a matching 512×512 PNG for each lives in `store/gamecenter-icons/`
(regenerate with `store/gamecenter-icons/generate.py`).

## Leaderboards (6)

All identical shape: **Classic** type · **Integer** format · **High to Low**
sort · English suffix `point` / `points` · score range blank. The app submits
the raw integer game score.

| Reference Name | Leaderboard ID | Display Name (EN) | Icon |
|---|---|---|---|
| Relaxed Best   | `lexis_leaderboard_relaxed` | Relaxed — Best Score | `lb_relaxed.png` |
| Classic Best   | `lexis_leaderboard_classic` | Classic — Best Score | `lb_classic.png` |
| Rapid Best     | `lexis_leaderboard_rapid`   | Rapid — Best Score   | `lb_rapid.png`   |
| Insane Best    | `lexis_leaderboard_insane`  | Insane — Best Score  | `lb_insane.png`  |
| Daily Challenge| `lexis_leaderboard_daily`   | Daily Challenge      | `lb_daily.png`   |
| Weekly Event   | `lexis_leaderboard_weekly`  | Weekly Event         | `lb_weekly.png`  |

- **Daily** — keep Classic; the app scopes the *view* to "today," so an
  all-time board works (`showDailyLeaderboard` uses `.today`).
- **Weekly** — Classic is fine (app tracks per-event best, view is `.allTime`).
  Switch to a **Recurring** board only if you want Game Center to auto-reset it
  weekly.

## Achievements (7)

All **single-step** (reported at 100% at once) → **Achievable More Than Once:
No**. Point total = **530** (Apple cap is 1000). Trigger column is the exact
condition from `AchievementTracker`.

| Reference Name | Achievement ID | Pts | Hidden | Triggers when | Icon |
|---|---|---|---|---|---|
| First Word        | `lexis_achievement_first_word`      | 5   | No   | 1st word ever cleared            | `ach_first_word.png` |
| Wordsmith         | `lexis_achievement_50_words`        | 25  | No   | 50 words cleared all-time        | `ach_50_words.png` |
| Lexicon           | `lexis_achievement_200_words`       | 75  | No   | 200 words cleared all-time       | `ach_200_words.png` |
| Seven-Letter Word | `lexis_achievement_seven_letters`   | 50  | No   | clear a word ≥ 7 letters         | `ach_seven_letters.png` |
| Combo Master      | `lexis_achievement_combo_5`         | 75  | No   | reach a 5-word combo             | `ach_combo_5.png` |
| Insane Survivor   | `lexis_achievement_insane_survivor` | 100 | Yes* | drop 100 tiles in one Insane run | `ach_insane_survivor.png` |
| Five Figures      | `lexis_achievement_score_10k`       | 100 | No   | score 10,000 in a single run     | `ach_score_10k.png` |

\* Insane Survivor is a good hidden/surprise reward; set Hidden = No if you'd
rather it be discoverable.

### Titles + descriptions (EN)

```
First Word
  Pre-earned: Clear your very first word.
  Earned:     You cleared your first word. The fall begins.

Wordsmith
  Pre-earned: Find 50 words in total.
  Earned:     50 words found — you're finding the rhythm.

Lexicon
  Pre-earned: Find 200 words in total.
  Earned:     200 words found. A true lexicon.

Seven-Letter Word
  Pre-earned: Clear a single word 7 letters or longer.
  Earned:     Seven letters in one word. Impressive reach.

Combo Master
  Pre-earned: Chain a 5-word combo in one run.
  Earned:     A five-word chain. Unstoppable tempo.

Insane Survivor
  Pre-earned: Drop 100 tiles in a single Insane run.
  Earned:     100 tiles on Insane. Nerves of steel.

Five Figures
  Pre-earned: Score 10,000 points in a single run.
  Earned:     10,000 points in one run. Elite.
```

## Notes

- ASC requires a **512×512 PNG (RGB, no alpha)** for every leaderboard and
  achievement — provided in `store/gamecenter-icons/`.
- None of this blocks TestFlight, but the leaderboards/achievements must exist
  in ASC before any score/achievement will post (even in sandbox/TestFlight).
