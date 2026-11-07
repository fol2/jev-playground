#!/bin/sh
# Move run data to the NAS by default: copy each item under runs/, check that the NAS holds the same
# file count and bytes, then delete the local copy. Kept local: runs/models (the engine loads them)
# and runs/001_wow_fishing/control (the live agent's files). Items changed in the last 10 minutes
# may belong to a live run and wait for the next sync.
#   sh tools/sync_runs.sh [--keep-local]
set -eu
cd "$(dirname "$0")/.."
nas_host=ds1819
nas_root=Claude/jev-playground/recordings
keep_local=${1:-}
ssh_nas() { ssh -o BatchMode=yes "$nas_host" "$@"; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

for item in runs/recordings/* runs/001_wow_fishing/* runs/002_wow_visual/*; do
  [ -e "$item" ] || continue
  case "$item" in runs/001_wow_fishing/control) continue ;; esac
  [ -z "$(find "$item" -mmin -10 -print -quit)" ] || { echo "$item busy, skipped"; continue; }
  case "$item" in
    runs/recordings/*) dest=$nas_root ;;
    runs/001_wow_fishing/*) dest=$nas_root/fishing ;;
    runs/002_wow_visual/*) dest=$nas_root/visual ;;
  esac
  name=$(basename "$item")
  ssh_nas "mkdir -p $dest"
  # tar over ssh: the NAS refuses remote rsync for this account.
  COPYFILE_DISABLE=1 tar --no-xattrs -C "$(dirname "$item")" -cf - "$name" | ssh_nas "tar -C $dest -xf -"
  # Every local file must be on the NAS with the same size (the NAS may hold more, e.g. older frames).
  (cd "$(dirname "$item")" && find "$name" -type f -exec stat -f '%z %N' {} + | LC_ALL=C sort) > "$tmp/local"
  ssh_nas "cd $dest && find '$name' -type f -exec stat -c '%s %n' {} + | LC_ALL=C sort" > "$tmp/nas"
  if [ -z "$(LC_ALL=C comm -23 "$tmp/local" "$tmp/nas")" ]; then
    [ "$keep_local" = "--keep-local" ] || rm -rf "$item"
    echo "$item -> $dest ($(wc -l < "$tmp/local" | tr -d ' ') files)"
  else
    echo "$item NOT freed: $(comm -23 "$tmp/local" "$tmp/nas" | wc -l | tr -d ' ') files missing or different on the NAS" >&2
  fi
done
