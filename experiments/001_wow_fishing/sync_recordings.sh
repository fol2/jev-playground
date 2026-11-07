#!/bin/sh
# Label each recorded fishing cast from its own events, then move all run data to the NAS
# (tools/sync_runs.sh frees local copies only when the NAS holds the same files and bytes). Labels are "auto" until a person or Jev corrects them.
#   sh experiments/001_wow_fishing/sync_recordings.sh [--keep-local]
set -eu
cd "$(dirname "$0")/../.."
for run in runs/001_wow_fishing/live_*/; do
  run=${run%/}
  [ -f "$run/events.jsonl" ] && [ ! -f "$run/label.json" ] || continue
  # Auto label from the cast's own log (first matching rule wins).
  label=$(python3 -I - "$run/events.jsonl" <<'EOF'
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
names = [e.get("event") for e in events]
bite = next((e["seconds"] for e in events if e.get("event") == "bite_candidate"), None)
if "loot_collected" in names: label = "caught"
elif "fish_got_away" in names: label = "fish_got_away"
elif "right_click" in names: label = "false_reel"
elif "stopped_no_visible_float" in names: label = "no_float"
elif "timed_out_without_click" in names: label = "no_bite_seen"
else: label = names[-1] if names else "empty"
print(json.dumps({"label": label, "label_source": "auto", "bite_seconds": bite}))
EOF
)
  printf '%s\n' "$label" > "$run/label.json"
done
exec sh tools/sync_runs.sh "$@"
