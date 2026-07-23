# LEXIS 2.1 — App Store submission walkthrough

Everything below is done in **App Store Connect** (appstoreconnect.apple.com) —
the parts I can't do from code. Do them roughly in this order. All the values
and assets referenced already exist in this repo.

Assets you'll need, all in `store/`:
- `app-store-listing.md` — every text field, paste-ready
- `screenshots/` — iPhone 6.9″ (01/02/03)
- `screenshots/ipad/` — iPad 13″ (01/02/03)
- `game-center-setup.md` + `gamecenter-icons/` — leaderboards, achievements, icons

The build to submit: **2.1 (build 4)** (universal, ads live). Wait for it to
finish "Processing" in TestFlight before you can select it.

---

## 0. First: test build 4 on a real device (do NOT skip)
Install 2.1 (build 4) from TestFlight on a physical iPhone and:
- [ ] Play a full run — **no crashes** (Guideline 2.1 is the #1 rejection cause,
      and there's now a third-party ad SDK running at launch).
- [ ] Hit a **"Watch → …"** button (start-with-boost on the menu, or the mid-run
      charge). You should see the **ATT prompt** → then a **real rewarded video**
      that grants the reward. If nothing plays, the ad unit is wrong (must be
      **Rewarded**, not Native) — stop and fix that before submitting. New units
      can also take a day to start filling; that's normal.
- [ ] Confirm notifications, Game Center sign-in, and haptics behave.

---

## 1. Create the 2.1 version
App Store Connect → **Apps → LEXIS → (+) macOS/iOS App … → App Store** tab →
if there's no "2.1" editable version, click the **(+) next to "iOS App"** in the
left sidebar and create version **2.1**.

---

## 2. Metadata (paste from `app-store-listing.md`)
On the 2.1 version page:
- [ ] **Promotional Text** (updatable anytime): the promo line
- [ ] **Description**: the full description block
- [ ] **Keywords**: `word,word game,puzzle,word puzzle,spelling,letters,anagram,brain,vocabulary,daily,scrabble,tetris`
- [ ] **Support URL**: `https://daviddef.github.io/Lexis/`
- [ ] **Marketing URL**: `https://daviddef.github.io/Lexis/`
- [ ] **What's New in This Version**: the v2.1 line from the listing
- [ ] **Version**: `2.1`

App-level (left sidebar → **App Information**), if not already set:
- [ ] **Name**: `LEXIS — Word Drop Puzzle`
- [ ] **Subtitle**: `Steer letters, spell words`
- [ ] **Category**: Primary **Games › Word**, Secondary **Games › Puzzle**
- [ ] **Privacy Policy URL**: `https://daviddef.github.io/Lexis/privacy.html`
- [ ] **Content Rights** → you own or have licensed all content: **Yes**

---

## 3. Screenshots (both device sizes are required)
On the 2.1 version page, scroll to the screenshot wells:
- [ ] **iPhone 6.9″ Display** → drag in `store/screenshots/01-menu.png`,
      `02-gameplay.png`, `03-gameover.png` (in order).
- [ ] **iPad 13″ Display** → drag in `store/screenshots/ipad/01-menu.png`,
      `02-gameplay.png`, `03-gameover.png`.

(Both are required because the app is universal — iPad can't be dropped, see
QA1623. ASC derives the smaller sizes from these.)

---

## 4. Build
- [ ] In the version page's **Build** section, click **(+)** and select
      **2.1 (build 4)**. (Only appears once it's done processing.)

---

## 5. App Privacy (this is the ads-critical part)
Left sidebar → **App Privacy → Edit**.
Declare **Data Used to Track You** (because AdMob serves personalized ads + the
app shows the ATT prompt — the label MUST match, or it's a Guideline 2.3
rejection):
- [ ] **Identifiers → Device ID** → *Used to Track You* → Yes
- [ ] **Usage Data / Advertising Data** (Third-Party Advertising) → *Used to
      Track You* → Yes
- Data is collected by the **third-party ad partner (Google AdMob)**, not linked
  to identity by you.
- Game Center is Apple-handled; nothing extra to declare for it.
- No analytics vendor is wired, so nothing there.

If unsure on any toggle, AdMob publishes a "privacy labels" mapping — search
"AdMob App Store data disclosure"; the safe minimum is the two above.

---

## 6. IDFA question (at submission)
When you submit, ASC asks **"Does this app use the Advertising Identifier
(IDFA)?"** → **Yes**. Then tick:
- [ ] **Serve advertisements within the app**
- [ ] Confirm you respect the ATT prompt (the app does).

---

## 7. Age rating
App Information → **Age Rating → Edit** → answer all "None" → results in **4+**.

---

## 8. Game Center (no new build needed)
This is the fiddliest part. Full field values + the 13 icons are in
`store/game-center-setup.md`.
1. [ ] On the **version page**, tick the **Game Center** checkbox.
2. [ ] Left sidebar → **Game Center** (or Services). Create:
   - **6 Leaderboards** — IDs `lexis_leaderboard_relaxed/classic/rapid/insane/
     daily/weekly`, Classic / Integer / High-to-Low, one 512×512 icon each from
     `store/gamecenter-icons/lb_*.png`.
   - **7 Achievements** — IDs `lexis_achievement_first_word/50_words/200_words/
     seven_letters/combo_5/insane_survivor/score_10k`, single-step, points +
     titles + descriptions from the doc, one icon each from `ach_*.png`.
3. [ ] Add them to the version's Game Center group for review.
   ⚠️ IDs must match **character-for-character** or scores silently never post.

---

## 9. Export compliance
Already handled in the build (`ITSAppUsesNonExemptEncryption: NO`), so ASC
shouldn't ask — if it does, answer **No** (no non-exempt encryption).

---

## 10. Pricing & availability
- [ ] **Price**: Free
- [ ] Availability: all territories (or your choice)

---

## 11. Submit
- [ ] **Add for Review → Submit**. Optionally set **Manual release** so you
      control the go-live moment after approval.

---

## Likely first-review pitfalls (worth a last look)
- **Ad SDK crash on the reviewer's device** → the on-device pass in step 0.
- **Privacy label ↔ ATT mismatch** → step 5 must reflect the ads.
- **Rewarded unit actually a Native unit** → confirmed in step 0.
- **Game Center IDs typo'd** → not a rejection, but leaderboards silently break.
- **iPad screenshots missing** → required now; step 3.
