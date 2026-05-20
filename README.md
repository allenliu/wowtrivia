# WoW Dungeon Trivia

Hear a voiceline from a World of Warcraft dungeon boss or NPC. Guess which dungeon it's from. 15 questions, ~5 minutes, share your result.

**Play:** [allenliu.github.io/wowtrivia](https://allenliu.github.io/wowtrivia)
**Browse the curated voiceline pool:** [/curate.html?browse=1](https://allenliu.github.io/wowtrivia/curate.html?browse=1)

## How it works

- Pool of curator-accepted voicelines lives in [data/game-pool.json](data/game-pool.json), generated from per-dungeon source files.
- Each game picks 15 questions: any `selected` quotes are always included; the rest fill randomly with max 1 per NPC and max 2 per dungeon.
- Audio streams directly from Wowhead's CDN (zamimg).
- Share URL encodes the run's actual sound IDs (packed 20-bit base64url, ~51 chars) so the link replays the same questions even after the pool changes.

Game scope: Legion → Midnight. Older expansions (Wrath/Cata/WoD) live in the pool but are excluded from random picks.

## Files

| Path | Purpose |
|------|---------|
| [`index.html`](index.html) | The game (single-file HTML/CSS/JS) |
| [`curate.html`](curate.html) | Curation UI — local edit via File System Access; `?browse=1` for read-only HTTP view |
| [`scripts/`](scripts/) | Tier-1/2 pipeline, Whisper transcription, pool builder, utilities |
| [`data/dungeons.json`](data/dungeons.json) | Catalog of 65 M+ dungeons (zoneId, slug, expansion) |
| [`data/tier2-configs/`](data/tier2-configs/) | Per-dungeon boss configs for the wiki+Whisper pipeline |
| [`data/voicelines-*.json`](data/) | Per-dungeon curation source of truth (one file per dungeon) |
| [`data/sounds-*.json`](data/) | Per-NPC manifests with cached Whisper transcripts |
| [`data/game-pool.json`](data/game-pool.json) | Aggregated accepted+selected quotes served to the game |
| [`voiceline-pipeline.md`](voiceline-pipeline.md) | How the scraping + curation pipeline works end-to-end |

## Run locally

It's a single-file game — open [`index.html`](index.html) directly in a browser, or serve the directory with any static server (the audio fetch requires HTTPS or `localhost`).

To curate, open [`curate.html`](curate.html) in Chrome/Edge and click **Open data folder** → pick this repo's `data/` directory. Changes save in-place via the File System Access API.

## Rebuilding the game pool

After accepting/rejecting quotes in `curate.html`:

```powershell
./scripts/build-game-pool.ps1
```

This regenerates [`data/game-pool.json`](data/game-pool.json) from every `data/voicelines-*.json`. Default filter is `status == 'accepted'`. See [voiceline-pipeline.md](voiceline-pipeline.md) for the full pipeline.

## Deploy

Pushes to `main` auto-deploy via GitHub Pages.
