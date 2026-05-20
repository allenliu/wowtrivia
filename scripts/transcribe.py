#!/usr/bin/env python3
"""
Transcribe cached .ogg files using Whisper. Reads a sounds-manifest JSON
(as produced by fetch-by-name.ps1), runs Whisper on each cached audio file,
writes the manifest back with `transcript` populated.

Idempotent: skips entries that already have a non-empty transcript unless
--force is passed.

Usage:
  python scripts/transcribe.py data/sounds-lord-chamberlain.json
  python scripts/transcribe.py data/sounds-lord-chamberlain.json --model base
"""

import argparse
import json
import sys
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", help="Path to sounds manifest JSON")
    parser.add_argument(
        "--model",
        default="small",
        choices=["tiny", "base", "small", "medium", "large"],
        help="Whisper model size (default: small)",
    )
    parser.add_argument("--cache", default="audio/cache", help="Directory of cached .ogg files")
    parser.add_argument("--language", default="English")
    parser.add_argument(
        "--force", action="store_true", help="Re-transcribe even if transcript already present"
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.exists():
        print(f"Manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    with manifest_path.open(encoding="utf-8") as f:
        data = json.load(f)

    sounds = data["sounds"]
    needs = [s for s in sounds if args.force or not s.get("transcript")]
    if not needs:
        print("All sounds already transcribed.")
        return

    print(
        f"Transcribing {len(needs)} of {len(sounds)} sounds with whisper-{args.model}...",
        flush=True,
    )
    print("Loading Whisper model (one-time setup)...", flush=True)

    # Imported lazily so --help doesn't pay the torch import cost.
    import whisper

    model = whisper.load_model(args.model)
    cache = Path(args.cache)

    start = time.time()
    done = 0
    failed = 0
    for s in needs:
        sid = s["soundId"]
        ogg = cache / f"{sid}.ogg"
        if not ogg.exists():
            print(f"  [{sid}] missing audio file, skipping", flush=True)
            failed += 1
            continue
        try:
            result = model.transcribe(str(ogg), language=args.language, fp16=False, verbose=False)
            s["transcript"] = result["text"].strip()
            done += 1
            if done % 5 == 0 or done == len(needs):
                rate = done / max(time.time() - start, 0.001)
                remaining = len(needs) - done
                eta = remaining / rate if rate > 0 else 0
                preview = s["transcript"][:70]
                print(
                    f"  [{done}/{len(needs)}] id={sid}: {preview!r}  ({rate:.2f}/s, ETA {eta:.0f}s)",
                    flush=True,
                )
        except Exception as e:
            print(f"  [{sid}] ERROR: {e}", flush=True)
            failed += 1

    # Save back atomically
    tmp = manifest_path.with_suffix(".tmp.json")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    tmp.replace(manifest_path)

    elapsed = time.time() - start
    print(f"\nDone. Transcribed {done} sounds in {elapsed:.0f}s (failed: {failed}).")
    print(f"Updated: {manifest_path}")


if __name__ == "__main__":
    main()
