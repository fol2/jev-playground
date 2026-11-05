#!/bin/sh
# Label each recorded fishing cast from its own events, copy it to the NAS, and free the local frames
# only after the NAS holds the same number of files. Labels are "auto" until a person or Jev corrects them.
#   sh experiments/001_wow_fishing/sync_recordings.sh [--keep-local]
set -eu
cd "$(dirname "$0")/../.."
nas_host=ds1819
nas_dir=Claude/jev-playground/recordings/fishing
keep_local=${1:-}
ssh -o BatchMode=yes "$nas_host" "mkdir -p $nas_dir"
for run in runs/001_wow_fishing/live_*/; do
  run=${run%/}
  [ -d "$run/frames" ] && [ -f "$run/events.jsonl" ] || continue
  # Auto label from the cast's own log (first matching rule wins).
  label=$(python3 -I - "$run/events.jsonl" <<'EOF'
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
names = [e.get("event") for e in events]
bite = next((e["seconds"] for e in events if e.get("event") == "bite_candidate"), None)
if "loot_collected" in names: label = "caught"
elif "right_click" in names: label = "false_reel"
elif "stopped_no_visible_float" in names: label = "no_float"
elif "timed_out_without_click" in names: label = "no_bite_seen"
else: label = names[-1] if names else "empty"
print(json.dumps({"label": label, "label_source": "auto", "bite_seconds": bite}))
EOF
)
  printf '%s\n' "$label" > "$run/label.json"
  name=$(basename "$run")
  # tar over ssh: the NAS refuses remote rsync for this account, plain ssh is enough.
  COPYFILE_DISABLE=1 tar --no-xattrs -C runs/001_wow_fishing -cf - "$name" | ssh -o BatchMode=yes "$nas_host" "tar -C $nas_dir -xf -"
  local_count=$(find "$run" -type f | wc -l | tr -d ' ')
  nas_count=$(ssh -o BatchMode=yes "$nas_host" "find $nas_dir/$name -type f | wc -l" | tr -d ' ')
  if [ "$local_count" = "$nas_count" ]; then
    [ "$keep_local" = "--keep-local" ] || rm -rf "$run/frames"
    echo "$name $(printf '%s' "$label" | python3 -c 'import json,sys; print(json.load(sys.stdin)["label"])') synced $nas_count files"
  else
    echo "$name NOT freed: local $local_count, NAS $nas_count" >&2
  fi
done
