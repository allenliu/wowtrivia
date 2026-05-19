# WoW Voiceline Trivia — Design Research Brief

**Goal:** Build a shareable, self-contained trivia game playable in 5–10 minutes, with a result card friends can screenshot or copy-paste, and a link they can share back.

---

## 1. Lessons from Viral Quiz Games

### The right comparisons: Sporcle + BuzzFeed quizzes + GeoGuessr Challenge mode

This game is a **one-time or one-sitting experience**, not a daily ritual. People play once, share their result, friends click out of curiosity. The design goal is "viral artifact" — the result card does the work of pulling new players in.

**Sporcle** — share a quiz link, anyone plays it anytime, compare scores. No daily dependency.
**GeoGuessr Challenge** — a seeded link creates a specific run anyone can replay; your score is attached to *that challenge*, not a calendar date.
**BuzzFeed/viral quizzes** — "I got X%, can you beat me?" on-demand, not daily.

Heardle is a useful reference for the **audio clip mechanic** only (short clip → guess the source). Its daily-puzzle social model does not apply here.

**Core design principle: the result card is the whole product.**
Since people aren't coming back daily, the card has to be compelling enough that a friend who hasn't played yet feels like they're missing out — even if they don't know WoW.

**Fixed question set, not seeded-random.**
Everyone plays the same 15 questions. When you post your result, your friends compete on the same run with no asterisks. Simpler to build.

**Zero friction to play.**
No account. No install. Open a link and start.

**Retry is fine, not the goal.**
Let people replay, but don't design for it. First-playthrough score is the real one.

---

## 2. Session Length & Question Count

**Target: 5–10 minutes = ~15 questions.**

- At 15 questions × ~25 seconds (audio clip + think + guess) = ~6 minutes
- NYT Mini Crossword and Connections: 3–7 minutes, the sweet spot for "shareable without being a commitment"
- Fixed set of 15 questions — everyone plays the same ones, always. No randomization needed for v1.
- Stratified across expansions (see section 8) so no era dominates

---

## 3. The Result Card — What Makes It Shareable

### Two shareable formats needed:

**A. Copy-paste text (WhatsApp, Discord, Slack)**
This is the Wordle pattern. Pure text/emoji, no image required, works anywhere.

Example format:
```
🔊 WoW Dungeon Trivia
Score: 11/15 ⚔️

🟩🟩🟩🟥🟩 🟩🟩🟥🟥🟩 🟩🟩🟩🟩🟥

Legion: ████ BfA: ███░ Shadowlands: █████
Can you beat me? → [link]
```

Key properties:
- Score visible immediately
- Grid shows *pattern* of right/wrong without spoiling answers
- Expansion breakdown adds bragging/trash-talk texture
- Link at the bottom drives new players in

**B. Screenshot-ready result card (Twitter/X, Reddit, group chats)**
A visually designed panel rendered in-browser that looks good when screenshotted. Should include:
- Big score: "11 / 15"
- Subtitle: rank/tier label ("High-Warlord" for high scores, "Fresh 70" for low)
- Per-dungeon or per-expansion breakdown as a visual bar/grid
- QR code or short URL to play

### Design principles for the card:
- **Score big and bold, above the fold** — the #1 thing people want to see
- **Color-coded pass/fail per question** — green/red grid
- **A "rank" label** rather than just a number (this is WoW-native language and is instantly relatable: "You got Grand Marshal. Your friend got Recruit.")
- **Encourage retakes and challenges** — "Can you beat [name]?" is more compelling than just a number

---

## 4. Rank System (WoW-Themed)

Instead of "67% correct," give a WoW PvP rank label. More shareable, more personality.

| Score | Rank |
|-------|------|
| 15/15 | Grand Marshal / High Warlord |
| 13–14 | Champion |
| 11–12 | Knight-Champion |
| 9–10 | Stone Guard |
| 7–8 | Grunt / Scout |
| 5–6 | Tracker |
| 0–4 | Fresh 70 |

---

## 5. The Shareable Link

Since everyone plays the same fixed question set, the link is simple:

**Play link:** `wow-trivia.example.com` — always the same game
**Result link:** `wow-trivia.example.com/result?score=11&breakdown=110110101110101` — encodes score and per-question right/wrong as a bitmask, reconstructs the result card client-side with no server needed

The breakdown bitmask is what powers the emoji grid in the copy-paste share. No database, no accounts, no backend required.

---

## 6. Question Flow — How Each Round Should Feel

**Input method: 4-option multiple choice (correct + 3 random wrong answers)**

The difficulty lives entirely in recognizing the audio, not in recalling dungeon names or navigating a list. Fast on mobile. No spelling issues.

Wrong answers are drawn randomly from the remaining 54 dungeons — no same-expansion requirement. Simple to implement and keeps the distractor logic trivial.

**Flow per question:**
1. Question counter visible (e.g. "3 / 15")
2. Large play button — clip does NOT auto-play (safer for quiet environments)
3. Replay button available at any time before guessing
4. 4 dungeon name buttons displayed — no expansion hint shown
5. On guess: immediate green/red highlight on all 4 buttons (correct answer always revealed), NPC name and quote shown as flavor text
6. "Next" button appears (no auto-advance — player controls pace)

---

## 7. Anti-Spoiler Sharing

The copy-paste result should never show which dungeon each question was. The grid of ✅/❌ shows *how many* you got right in each block, not *which* ones. This way:
- People who haven't played yet are intrigued, not spoiled
- Multiple people can share results from the same set and compare

---

## 8. Recommended Question Set Structure

For a 15-question run, stratify by expansion to avoid over-indexing:

| Expansion | Questions |
|-----------|-----------|
| Legion | 3 |
| WoD | 1 |
| BfA | 2 |
| Cataclysm | 1 |
| Shadowlands | 2 |
| WotLK | 1 |
| Dragonflight | 2 |
| War Within | 3 |

This gives representation across eras, with heavier weight on recent content (War Within, Dragonflight) where players have fresher memory.

---

## 9. Accessibility Notes

- Always show the dungeon name in the answer reveal (not just color), for players who are colorblind or sharing as text
- Transcript / quote text shown after the answer reveal, in case audio failed to load
- Replay button mandatory — some clips may be quiet or contextually confusing

---

## 10. Implementation Path

| Phase | What |
|-------|------|
| 1 | Static HTML/JS game with hardcoded question set, hosted on GitHub Pages or Netlify |
| 2 | Add URL-encoded result state (bitmask in URL, no server needed) |
| 3 | Add copy-paste text share + screenshot-ready result card |
| 4 | (Optional) Multiple question sets / "shuffle" for replays |
| 5 | (Optional) Leaderboard via simple backend or Airtable |

Phases 1–3 are fully client-side. No backend, no accounts, no server costs.

---

## 11. Visual Style

**WoW UI aesthetic** — parchment/stone textures, gold borders, serif fantasy fonts, the warm brown/gold palette of the classic WoW interface. Reference: the in-game tooltip, quest log, and achievement panel aesthetic.

Key elements:
- Dark stone or aged parchment background
- Gold/amber border frames on panels and buttons
- Button states: default (stone), hover (gold glow), correct (green gem), wrong (red gem)
- Font: a serif or fantasy display font for headers; clean sans-serif for body text
- NPC quote revealed after each answer styled like an in-game tooltip or quest text
- Result card designed to look like a WoW achievement panel

- [ ] 15 questions, ~6–8 minute session
- [ ] Multiple choice (4 options, same-era distractors)
- [ ] Audio clip plays on question load, with replay button
- [ ] Immediate right/wrong feedback with NPC name revealed
- [ ] Result card: big score, WoW rank label, expansion breakdown grid
- [ ] Copy-paste text share (emoji grid + link)
- [ ] Screenshot-friendly result panel
- [ ] Shareable link encodes question set + result (no server needed)
- [ ] No login, no install, opens in browser instantly
