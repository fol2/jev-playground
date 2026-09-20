"""Stream the pilot clip into small colour/motion measurements; optionally ask Jev four times.

This fixed ROI is calibrated for the first pilot, not a general bobber tracker.
"""

import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MODEL = "jev-1.13.0"
CHECKPOINTS = (8.0, 12.0, 19.5, 20.0)
QUESTION = {
    "type": "choice",
    "instructions": (
        "Choose a fishing response from the recent measured observations only. "
        "A bite may produce an abrupt downward bobber movement and temporary disappearance. "
        "A fixed colour mask is not a verified object tracker: lighting, cursor overlap and "
        "occlusion can confound it. Do not invent splash or audio evidence. "
        "Downward movement increases y_px. All changes use 0–255 RGB intensity units. "
        "Do not treat ordinary gradual bobbing as a bite."
    ),
    "criteria": {
        "WAIT": "The target remains visible and its movement is consistent with ordinary waiting.",
        "REEL": "The recent sequence provides clear evidence of an abrupt bite-like movement at the target.",
        "ABSTAIN": "The target or evidence is absent, unreliable, conflicting or insufficient.",
    },
}


def rules(state):
    history = state["recent_observations"]
    if len(history) < 6:
        return "ABSTAIN"
    current, prior = history[-1], history[:-1]
    if any(row["orange_pixels"] < 100 for row in prior):
        return "ABSTAIN"
    baseline_y = statistics.median(row["y_px"] for row in prior)
    baseline_area = statistics.median(row["orange_pixels"] for row in prior)
    if (current["y_px"] is not None and current["y_px"] - baseline_y >= 6
            and current["orange_pixels"] < baseline_area * 0.5
            and current["background_change"] < 4):
        return "REEL"
    return "WAIT" if current["orange_pixels"] >= 100 else "ABSTAIN"


def api_key():
    key = os.environ.get("TYPESAFE_API_KEY", "").strip()
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text().splitlines():
            name, sep, value = line.removeprefix("export ").partition("=")
            if sep and name.strip() == "TYPESAFE_API_KEY":
                key = value.strip().strip("\"'")
    if not key:
        raise SystemExit("Set TYPESAFE_API_KEY in the environment or local .env")
    return key


def ask(state, key):
    request = {"model": MODEL, "state": state, "questions": {"action": QUESTION}}
    req = urllib.request.Request("https://api.typesafe.ai/v1/systemone",
                                 data=json.dumps(request).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + key,
                                          "Content-Type": "application/json"})
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.load(response)
        answer = result["answers"]["action"]
        probs = answer["probabilities"]
        if (answer["type"] != "choice" or answer["choice"] not in QUESTION["criteria"]
                or set(probs) != set(QUESTION["criteria"])
                or not all(type(p) in (int, float) and 0 <= p <= 1 for p in probs.values())
                or abs(sum(probs.values()) - 1) > 0.02
                or not 0 <= answer["confidence"] <= 1
                or result["model"] != MODEL):
            raise ValueError("Unexpected answer schema or model")
        return {"request": request, "response": result,
                "request_seconds": round(time.monotonic() - start, 4)}
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError, TypeError) as exc:
        # Do not persist response bodies or exception strings containing credentials.
        return {"request": request, "error": type(exc).__name__,
                "http_status": getattr(exc, "code", None),
                "request_seconds": round(time.monotonic() - start, 4)}


def measurements(video):
    probe = subprocess.check_output([
        "ffprobe", "-v", "error", "-read_intervals", "%+36", "-select_streams", "v:0",
        "-show_frames", "-show_streams", "-show_entries",
        "stream=width,height,time_base:frame=best_effort_timestamp_time", "-of", "json", str(video)])
    info = json.loads(probe)
    if [(s["width"], s["height"]) for s in info["streams"]] != [(680, 440)]:
        raise ValueError("The pilot ROI requires a 680 x 440 recording")
    timestamps = [float(frame["best_effort_timestamp_time"])
                  for frame in info["frames"]]
    if not timestamps or timestamps[-1] - timestamps[0] > 35:
        raise ValueError("Use the short pilot clip (at most 35 seconds)")
    command = ["ffmpeg", "-v", "error", "-threads", "1", "-i", str(video),
               "-map", "0:v:0", "-vf", "crop=180:160:60:200", "-fps_mode", "passthrough",
               "-enc_time_base", info["streams"][0]["time_base"],
               "-pix_fmt", "rgb24", "-threads", "1",
               "-f", "rawvideo", "pipe:1"]
    previous = None
    next_sample = 0.0
    with subprocess.Popen(command, stdout=subprocess.PIPE) as process:
        try:
            for timestamp in timestamps:
                raw = process.stdout.read(180 * 160 * 3)
                if len(raw) != 180 * 160 * 3:
                    raise ValueError("Incomplete decoded frame")
                t = timestamp - timestamps[0]
                if t < next_sample:
                    continue
                next_sample = t + 0.1
                frame = np.frombuffer(raw, np.uint8).reshape(160, 180, 3).astype(np.int16)
                target = frame[45:105, 40:115]
                r, g, b = target.transpose(2, 0, 1)
                mask = (r > 100) & (r - g > 15) & (g - b > 15)
                y, x = np.nonzero(mask)
                delta = np.abs(frame - previous) if previous is not None else np.zeros_like(frame)
                yield {"t_s": round(t, 4), "orange_pixels": len(x),
                       "y_px": round(float(y.mean()) + 245, 2) if len(x) else None,
                       "target_change": round(float(delta[45:105, 40:115].mean()), 3),
                       "background_change": round(float(delta[:40, 120:].mean()), 3)}
                previous = frame
            if process.wait() != 0:
                raise RuntimeError("Video decoding failed")
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.terminate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("--jev", action="store_true", help="Send four measured states to Jev; no retries")
    args = parser.parse_args()
    key = api_key() if args.jev else None
    run = ROOT / "runs" / "001_wow_fishing" / (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8])
    run.mkdir(parents=True)
    history = deque(maxlen=6)
    checkpoints = []
    reel_times = []
    started = time.monotonic()
    with (run / "observations.jsonl").open("w") as output:
        for row in measurements(args.video):
            history.append(row)
            state = {"target": "manually located bobber region in the pilot recording",
                     "measurement": "fixed orange colour mask, not object tracking; cursor may overlap",
                     "audio": "not used", "recent_observations": list(history)}
            action = rules(state)
            output.write(json.dumps({**row, "rules": action}) + "\n")
            # Pilot comparison ends before the observed retrieval/loot response.
            if action == "REEL" and row["t_s"] <= 20.8:
                reel_times.append(row["t_s"])
            if len(checkpoints) < len(CHECKPOINTS) and row["t_s"] >= CHECKPOINTS[len(checkpoints)]:
                checkpoints.append({"t_s": row["t_s"], "state": state, "rules": action})
    analysis_seconds = round(time.monotonic() - started, 4)
    with (run / "comparison.jsonl").open("w") as output:
        for item in checkpoints:
            if key:
                item["jev"] = ask(item["state"], key)
            output.write(json.dumps(item) + "\n")
            output.flush()
            answer = item.get("jev", {}).get("response", {}).get("answers", {}).get("action", {})
            print(json.dumps({"t_s": item["t_s"], "rules": item["rules"],
                              "jev": answer.get("choice"),
                              "confidence": answer.get("confidence"),
                              "error": item.get("jev", {}).get("error")}))
    with args.video.open("rb") as source:
        video_hash = hashlib.file_digest(source, "sha256").hexdigest()
    summary = {"video": str(args.video), "sha256": video_hash,
               "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "numpy_version": np.__version__,
               "analysis_seconds": analysis_seconds, "rules_reel_times_before_retrieval": reel_times,
               "first_accepted_reel": reel_times[0] if reel_times else None,
               "api_calls": len(checkpoints) if key else 0,
               "limitation": "One development clip; fixed ROI and provisional thresholds, no held-out test"}
    (run / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"Results: {run}")


if __name__ == "__main__":
    main()
