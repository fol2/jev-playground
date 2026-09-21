# Fishing animation pilot — 21 September 2026

Five human-played casts were recorded. The owner confirmed seeing a bite and
successfully collecting fish on all five. The agent cast and recorded; it did not
reel automatically. No Jev calls were made. These are development observations,
not an autonomous success-rate test or a held-out evaluation.

## What the recordings establish

The [sampled animation frames](splash-sequences.png) show casts 1, 3, 4 and 5 with
a similar short sequence: float movement/rotation, a burst of local spray/ripples,
and return to the ordinary appearance. The spray extends beyond the float body.
This supports investigating temporal appearance changes, rather than relying only
on an estimated tracking-box displacement. It does not establish pixel-identical
animation or a reliable detection threshold.

The gear-shaped hover cursor is visible before, during and after the bite in
several casts. It indicates interaction availability, not bite onset. Cursor
motion/appearance must not become the bite signal. Cast 1 also contains a visible
splash without the cursor beside the float at that moment.

The strips are sampled at the exact source frame indices/PTS in
[sampled-frames.json](sampled-frames.json). They illustrate the sequence but are
not exhaustive frame-by-frame onset labels. Approximate review intervals are in
[manifest.json](manifest.json); exact earliest visual onset remains to be labelled.
The bite and human retrieval times are distinct.

Cast 2 was cut off before the event/retrieval was captured. Its human-confirmed
success does not make its video complete, and it must not be labelled a no-bite
negative. Casts 1, 3, 4 and 5 show the subsequent loot window in the recording.

## Capture and retention

- Observed window bounds: (0, 0, 2560, 1440). Full-screen/windowed mode and UI-scale
  setting were not independently classified; this pilot uses one fixed geometry.
- Window-only crop: (750, 250, 1000, 550), encoded at 1000 x 550; requested 30 fps,
  actual presentation timestamps retained. Cursor included, audio disabled.
- Initial 35-second clips could end too early because capture started before the
  input call. Casts 4 and 5 used a 45-second limit.
- Retained detail crop: (440, 160, 280, 240) within the recording, without spatial
  resizing or frame-rate reduction. This is a manually selected analysis region,
  not proof that automatic acquisition works.
- Cropped H.264 was encoded losslessly relative to the decoded capture. Source
  capture itself was H.264, not a lossless screen master. Per-frame decoded hashes
  and timestamps were compared before deleting larger duplicates.
- Five detail videos plus metadata and one context still per cast occupy about
  20.7 MB locally under `data/001_wow_fishing/pilot_20260921/`. Full videos stay out
  of Git; this folder contains only a small review sheet, manifest and findings.
- Source and retained file hashes remain in the manifest. The bounded recorder
  source is retained with the local data as `recorder.swift`.

The initial recording attempts contained only four frames and were excluded.
After changing the capture queue from 3 to 8 and setting the helper activation
policy to prohibited, a three-second probe captured 90 frames. These changes were
made together, so the pilot does not isolate the exact cause of that capture fault.
All five retained clips were verified by decoded frame counts (1028, 997, 1006,
1309, 1252), rather than trusting a recording-complete callback.

## Next decision

Use these small clips to compare local appearance change around the float with
ordinary bobbing and cursor motion. Test the proposed observations at 30, 15 and
10 fps using actual timestamps before choosing a runtime sampling rate. Do not
add another tracking fallback or tune a downward-pixel threshold solely on these
four positives. A new scene/scale and complete held-out casts remain necessary.
No live detector, policy or input behaviour was changed during this pilot.
