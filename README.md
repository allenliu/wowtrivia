# WoW Dungeon Trivia

A shareable, self-contained trivia game: hear a voiceline from a World of Warcraft dungeon boss or NPC, guess which dungeon it's from. 15 questions, ~6–8 minutes, copy-paste a result card to challenge friends.

**Status:** Phase 1 — prototype HTML game built, 2 of 15 audio sources wired, rank system and self-hosted audio still TODO.

## Files

| File | Purpose |
|------|---------|
| `wow-trivia.html` | The game (single-file HTML/CSS/JS) |
| `wow-mplus-voicelines.md` | Dataset of ~368 candidate voicelines |
| `wow-trivia-design-research.md` | Design decisions and rationale |
| `wow-trivia-ranks.md` | Rank system options + suggested set |
| `wow-dungeon-trivia.jsx` | Earlier NPC-image trivia concept (archived) |

## Run locally

It's a single HTML file — open `wow-trivia.html` in a browser, or serve the directory with any static server.

## Roadmap

See [wow-trivia-design-research.md](wow-trivia-design-research.md) §10 for full phases. Near-term:

- [ ] Fill in remaining 13 Wowhead sound IDs
- [ ] Self-host audio files (`/audio/` folder)
- [ ] Wire suggested lore-character rank set from [wow-trivia-ranks.md](wow-trivia-ranks.md)
- [ ] URL-encoded result state for shareable result links
- [ ] GitHub Pages deploy
