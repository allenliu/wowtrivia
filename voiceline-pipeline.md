# Voiceline Scraping + Curation Pipeline

How the game pool gets built, from "this dungeon exists" to "playable in [index.html](index.html)".

## The goal

For each M+ dungeon, find 3–5 iconic voicelines (audio + text + NPC + dungeon) that a player would recognize. Quality bar:

- Audio must actually be the boss/NPC saying the line (no misattributed clips).
- Text and audio should match (Whisper transcripts let us spot-check this).
- The line should be evocative enough that someone who's played the dungeon goes "oh, I know that one."

The hand-picked set goes into [data/game-pool.json](data/game-pool.json), which [index.html](index.html) loads at runtime.

## Two-tier sourcing strategy

Most NPCs aren't in any single place where text and audio are pre-paired. We use two paths and merge them.

### Tier 1 — Wowhead "Quotes" sections

A subset of NPCs on Wowhead have a curated **Quotes** tab with paired (text, sound clip) entries. This is the gold standard — Wowhead's editors already did the matching.

- Scraper: [scripts/fetch-dungeon-quotes.ps1](scripts/fetch-dungeon-quotes.ps1)
- Input: a `zone` ID (from [data/dungeons.json](data/dungeons.json))
- It iterates every NPC the zone page lists, fetches their Wowhead NPC page, and looks for an embedded "Quotes" Listview.
- Output: `data/voicelines-<slug>.json` with NPCs and their paired quotes.

Caveats:
- The zone NPC list is broader than "actually appears in this dungeon" — some NPCs are listed from open-world questing. We post-filter NPCs whose `location` array includes the zone ID.
- Some characters (e.g., Alleria Windrunner) have multiple NPC IDs for the same voice. We dedupe by sound ID.
- Wowhead is fronted by CloudFront WAF — bare `Invoke-WebRequest` gets 403'd. The scraper sends a full browser header set (Accept, Accept-Language, Sec-Fetch-*, Sec-Ch-Ua-*, etc.). When blocked, it backs off 30/60/120s.

### Tier 2 — wiki text + Whisper transcription + fuzzy match

For NPCs without a Wowhead Quotes section, we synthesize the pairing:

1. **Find candidate sound files** by NPC name. Wowhead's sound search at `/sounds?filter=na=<substring>` returns all sound clips whose filename contains the substring. Filenames are conventionally `VO_<patch>_<NPC>_<NN>_<actor>.ogg`.
2. **Download each .ogg** to `audio/cache/` (gitignored, regenerable).
3. **Transcribe** with OpenAI Whisper (`small` model, English). ~1 sec/clip on CPU.
4. **Hand-enter wiki text** in [data/tier2-configs/<slug>.json](data/tier2-configs/) — paste from warcraft.wiki's boss page Quotes section.
5. **Fuzzy match** wiki text against Whisper transcripts (normalized Levenshtein, threshold 0.55). Successful matches become `source: "wiki"` entries with both the wiki text and Whisper transcript stored.
6. **Bonus pool** — any unmatched transcript ≥ 10 chars becomes a `source: "transcript"` entry, in case the wiki list was incomplete.

Orchestrator: [scripts/build-tier2.ps1](scripts/build-tier2.ps1). It calls [fetch-by-name.ps1](scripts/fetch-by-name.ps1) → [transcribe.py](scripts/transcribe.py) → match.

The Tier-2 config schema (per dungeon):

```json
{
  "dungeon": "Halls of Atonement",
  "slug": "halls-of-atonement",
  "wowheadZoneId": 12831,
  "expansion": "Shadowlands",
  "bosses": [
    {
      "id": 164218,
      "name": "Lord Chamberlain",
      "filterName": "lord_chamberlain",                   // Wowhead substring filter
      "namePattern": "^VO_901_Lord_Chamberlain_",         // optional regex to scope to one patch
      "quotes": [
        { "context": "Aggro", "text": "Behold the splendor of the master..." }
      ]
    }
  ]
}
```

### Transcript-only path (no wiki text available)

For bosses with no wiki quote list — e.g., Mistcaller, Mogul Razdunk, or unreleased Midnight content — the boss entry has `quotes: []`. The Tier-2 build still fetches and transcribes their sounds; every transcript becomes a `source: "transcript"` bonus entry pending curator approval. Worked example: [data/tier2-configs/nexus-point-xenas.json](data/tier2-configs/nexus-point-xenas.json) (Corewarden Nysarra's 14 lines, all transcript-only).

## Per-quote data schema

Every quote in `data/voicelines-<slug>.json` carries enough info to support curation and replay:

```json
{
  "soundId": 156541,
  "filename": "VO_901_Lord_Chamberlain_01_M",
  "audioUrl": "https://wow.zamimg.com/sound-ids/live/enus/.../VO_901_Lord_Chamberlain_01_M.ogg",
  "text": "Behold the splendor of the master...",
  "source": "wiki",           // wiki | transcript | wowhead
  "wikiContext": "Aggro",     // null for transcript-only
  "transcript": "Behold the splendor of the master.",
  "matchScore": 0.91,         // Levenshtein similarity, null for Tier-1/transcript-only
  "status": "accepted",       // pending | accepted | rejected   ← curator
  "selected": true,           // ★ always-include in every game   ← curator
  "notes": ""
}
```

`status` and `selected` are the only fields touched by curation — everything else is mechanical.

## Curation workflow ([curate.html](curate.html))

[curate.html](curate.html) is a single-file in-browser tool that uses the **File System Access API** to read and write the `data/voicelines-*.json` files in place. Chrome/Edge only.

For each quote you can:

- **✓ Accept** — quote is good, eligible for the game pool.
- **✗ Reject** — bad audio, wrong NPC, dialogue mismatch, etc.
- **◆ Clear** — return to `pending`.
- **★ Selected** — must appear in every game (independent of accept/reject).

The header shows source filters (Wiki / Wowhead / Transcript) so you can hide the bonus transcript noise while spot-checking Tier-1 entries.

A Review mode (toggle in header) gives a per-dungeon summary table sorted by accepted count, with click-to-jump navigation.

NPC IDs link to their Wowhead page so you can verify "is this really X talking?"

## Generating the game pool

[scripts/build-game-pool.ps1](scripts/build-game-pool.ps1) walks every `data/voicelines-*.json`, applies the filter, and writes [data/game-pool.json](data/game-pool.json).

Default filter:

- `status == 'accepted'` (curator's pick)
- `selected` flag is preserved on output

Switches:

- `-IncludePending` — also include `pending`/unset quotes (useful while curating).
- `-OutputFile <path>` — write elsewhere.

The output schema is intentionally flat — one record per playable quote, no NPC grouping:

```json
{
  "generated": "2026-05-19T19:28:00-07:00",
  "count": 108,
  "selected": 2,
  "filter": "accepted-only",
  "quotes": [
    { "soundId": 156541, "text": "...", "audioUrl": "...",
      "npc": "Lord Chamberlain", "dungeon": "Halls of Atonement",
      "expansion": "Shadowlands", "source": "wiki", "selected": true }
  ]
}
```

[index.html](index.html) fetches this on page load, filters by expansion (Legion → Midnight), and runs `pickRandomQuestions` with rules:

- All `selected: true` quotes go in first (NPC-deduped).
- Remaining slots fill randomly with max 1 per NPC and max 2 per dungeon.
- Final order is shuffled so selected quotes don't always land at the start.

## Adding a new dungeon — recipe

1. **Catalog**: add the dungeon to [data/dungeons.json](data/dungeons.json) with its Wowhead `zoneId`, slug, expansion.
2. **Tier 1 first**: `scripts/fetch-dungeon-quotes.ps1 -ZoneId <id>`. If you get a few NPCs with quote pairs, you're done — curate and move on.
3. **Tier 2 if sparse**: drop a new config in [data/tier2-configs/<slug>.json](data/tier2-configs/) listing each boss's NPC ID, a `filterName` substring, optional `namePattern` regex, and (if available) wiki quote text. Run `scripts/build-tier2.ps1 -ConfigFile <path>`.
4. **Curate**: open [curate.html](curate.html), point it at `data/voicelines-<slug>.json`, accept the good ones.
5. **Rebuild pool**: `scripts/build-game-pool.ps1` (default settings).
6. **Commit**.

## Caveats and known limits

- **CloudFront WAF**: Wowhead occasionally blocks the scraper. Use the cached HTML in `.cache/wowhead/` (gitignored) for re-runs; the scraper checks the cache before each request.
- **Filename quirks**: Wowhead's `filter=na=` strips some punctuation. `ki_katal` returns 0; `kikatal` works. `alun_za` fails; `alunza` works. Try without underscores if a search comes up empty.
- **Whisper hallucinations**: short clips of yells or grunts sometimes produce nonsense English transcripts ("Subscribe to my channel!"). The `MinBonusChars = 10` filter helps but doesn't catch everything — visual inspection in [curate.html](curate.html) is the safety net.
- **Multiple NPCs, same voice**: characters like Alleria Windrunner have multiple Wowhead NPC IDs for the same in-game character; sound IDs overlap. The Tier-1 scraper dedupes by `soundId` at write time.
- **Unreleased content** (Midnight): voicelines for unreleased bosses may not exist or may be placeholders. Skip until release.

## Reverse-lookup utility

[scripts/find-sound-dungeon.ps1](scripts/find-sound-dungeon.ps1) — paste any Wowhead sound URL, sound ID, or filename, and it'll tell you which dungeon's NPC owns it by cross-referencing the cached zone NPC listings. Handy when you find a clip in the wild and want to add it to the right config.
