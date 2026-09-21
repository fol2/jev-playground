# Parallel investigation snapshot — 21 September 2026

The owner explicitly authorised sharing all retained fishing videos and experiment
records on GitHub. This is a one-off exception to keeping captures out of Git;
credentials and machine-specific camera setup receipts remain local.

- Source: branch `experiment/test-b-parity`.
- Videos, context images, capture metadata and labels: `data/001_wow_fishing/`.
  [File checksums](shared-recordings.json) cover the 39 shared files (66,075,582 bytes).
- Historical run records: GitHub Release `fishing-evidence-20260921`, asset
  `jev-fishing-runs-20260921.tar.gz` (137,781,611 bytes), SHA-256
  `0234f22d20ef1b6146f77a86e7d53b7a64fde61fb1284b0eaeb09b6a2e04d808`.
  The archive expands to `runs/001_wow_fishing/` and contains the complete existing
  run directory before this investigation; do not mistake historical results for
  current-source acceptance.

```sh
git fetch origin
git switch --track origin/experiment/test-b-parity
# Optional historical diagnostics; not needed for video analysis:
gh release download fishing-evidence-20260921 --repo fol2/jev-playground \
  --pattern jev-fishing-runs-20260921.tar.gz
```

Start with `angles_20260921/README.md` and `session.json`: high-02 and far-02 are
complete human-confirmed positives. Far-01 has a 17.768-second capture gap;
high-01 is unsuccessful and incomplete. The five earlier pilot casts have human
labels, but cast-02 ends early and exact original PTS preservation is unproven.
Use the earlier batch for appearance, not precise timing claims. The oldest MOV
is an unlabelled initial recording. Do not quietly discard failed/ambiguous cases.

All clips are development data. A new autonomous five-minute Test A is still
required. Preserve identical observations for later A/B comparison; do not feed
manual labels or the rules verdict to Jev. No further model calls are needed to
investigate the rules policy.
