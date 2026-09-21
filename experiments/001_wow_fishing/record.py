"""Record one small, silent macOS screen region; no model calls or input events."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import uuid


def rectangle(value):
    try:
        x, y, width, height = map(int, value.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Use x,y,width,height in desktop coordinates") from exc
    if not (0 < width <= 1000 and 0 < height <= 1000):
        raise argparse.ArgumentTypeError("Width and height must be between 1 and 1000")
    return f"{x},{y},{width},{height}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rect", required=True, type=rectangle)
    parser.add_argument("--seconds", type=int, choices=range(1, 31), default=30,
                        metavar="1..30")
    parser.add_argument("--dry-run", action="store_true", help="Print settings without recording")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This recorder requires macOS")
    folder = Path(__file__).resolve().parents[2] / "data" / "001_wow_fishing"
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8]
    output = folder / f"{run_id}.mov"
    command = ["/usr/sbin/screencapture", "-v", "-x", f"-V{args.seconds}",
               f"-R{args.rect}", str(output)]
    if args.dry_run:
        print(json.dumps({"command": command, "audio": False, "model_calls": 0}, indent=2))
        return
    folder.mkdir(parents=True, exist_ok=True)
    metadata = {"started_at_utc": datetime.now(timezone.utc).isoformat(),
                "desktop_rect": args.rect, "requested_seconds": args.seconds,
                "audio": False, "status": "started", "file": output.name}
    note = output.with_suffix(".json")
    note.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Recording for {args.seconds} seconds: {output}", flush=True)
    try:
        subprocess.run(command, check=True, timeout=args.seconds + 15)
        if not output.exists() or output.stat().st_size == 0:
            raise RuntimeError("No recording produced; check Screen Recording permission")
    except (subprocess.SubprocessError, OSError, RuntimeError) as exc:
        metadata["status"] = "failed"
        print(f"Recording failed: {exc}", file=sys.stderr)
        code = 1
    else:
        metadata["status"] = "captured_unreviewed"
        metadata["bytes"] = output.stat().st_size
        print(f"Saved {metadata['bytes'] / 1024 / 1024:.2f} MiB; inspect before using as evidence.")
        code = 0
    metadata["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    note.write_text(json.dumps(metadata, indent=2) + "\n")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
