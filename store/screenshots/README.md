# LEXIS — App Store screenshots

6.9″ iPhone (1320 × 2868), captured from the iPhone 17 Pro Max simulator.
App Store Connect derives the smaller iPhone sizes from these.

| File | Screen | Suggested caption |
|---|---|---|
| `01-menu.png`     | Menu — glowing wordmark + all modes | **One letter. One word. One life.** |
| `02-gameplay.png` | Ocean scene, 3 words glowing (PLAY across, PUZZLED across, WORD down) | **Words read 8 ways — even diagonally** |
| `03-gameover.png` | Game Over — new top score, words made | **Chase your best** |

## How these were made
Captured via the DEBUG-only screenshot harness (see `LEXIS_SHOT` in
`GameView.swift` + `debugSeedMidGame` / `debugSeedGameOver` in `GameModel.swift`).
The harness seeds a photogenic state and skips the ATT prompt so it never
covers a shot. To regenerate:

```
xcrun simctl status_bar <PM-udid> override --time "9:41" --batteryLevel 100 \
  --batteryState charged --cellularBars 4 --wifiBars 3 --dataNetwork wifi
for s in menu game gameover; do
  SIMCTL_CHILD_LEXIS_SHOT=$s xcrun simctl launch <PM-udid> com.daviddefranceski.lexis
  sleep 5; xcrun simctl io <PM-udid> screenshot shot_$s.png
done
```

## Still worth adding (optional, stronger listing)
- **Collection** (themes + bursts + backdrops) — "Collect themes, bursts & backdrops"
- **A big combo / clear-burst firing** — "Chain words for huge combos"
- **iPad 13″** set — only if iPad ships (2.0 is iPhone-only per the roadmap).

Apple requires ≥1 screenshot and allows up to 10; these three are a solid
minimum. Consider adding captions/device frames in a tool before uploading —
the raw frames here match the live UI exactly (Guideline 2.3).
