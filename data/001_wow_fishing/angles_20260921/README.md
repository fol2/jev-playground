# Camera and distance pilot

The owner authorised checking native camera save/restore and a small angle/distance
recording batch. No character movement or heading keys, automatic reel, game-memory
reads or Jev requests were used. The camera was returned to the saved visible-water
baseline after recording.

## Native view controls verified in this beta

Options > Key Bindings > View Functions exposes Set View 1–5 and Save View 1–5.
Previously unbound Set View 1 is now Control+Option+F9; Save View 1 is
Control+Option+F10. Character-specific bindings were unchecked, so these are not
claimed to be character-only. They remain configured for the owner.

Save View 1, a left-button pitch change to near-overhead, then Set View 1 visibly
restored the saved pitch. A visible-water baseline was subsequently saved. Two
scroll-out actions reduced avatar size; Set View 1 restored the baseline framing
and avatar size. These are screenshot observations, not numeric camera-angle
measurements. Restart persistence, windowed/full-screen transitions and automated
background pre-go invocation of these bindings remain untested.

## Cast outcomes and evidence limits

- high-01: owner saw casting but reported no successful collection. CUA rejected
  several actions for user-state drift before eventual casting. The initial clip
  contains no visible cast in the inspected frames; retain its context image and
  provenance. The separate tail captures the end of the failed attempt. Do not
  label it a complete ordinary/no-bite negative.
- high-02: owner confirmed bite and collection; no capture gaps over 250 ms.
- far-01: owner confirmed bite and collection, but the video has a 17.768-second
  gap between 4.657 and 22.425 seconds and another 0.333-second gap. Exclude it from
  complete bite-animation or timing evaluation. Do not invent intermediate frames.
- far-02: owner confirmed bite and collection; no capture gaps over 250 ms.

Position was visibly 65.1,73.2 throughout this batch, whereas the earlier batch was
65.3,72.7. The camera-angle comparison with the old batch is therefore confounded
by position and scene. The two distances within this batch used the same position
and no intentional pitch/heading change. Numerical zoom factors were not read.
Window bounds remained 2560 x 1440; no window-mode or UI-scale comparison was run.

## Retention

Four local detail videos retain failed/incomplete outcomes as well as successes.
They are cropped, not spatially downscaled, and losslessly encoded relative to the
already H.264-compressed source. `session.json` records source/retained hashes,
crops, PTS gaps and human labels. Direct decoded-frame hashes and original PTS were
verified before removal of larger duplicates. The original 1/600 time base is
explicitly preserved. This batch totals about 32.7 MB including context stills.
No further recordings are running.

The previous animation pilot's time verification compared normalised decoder
output rather than directly checking original packet/frame timestamps. Its visual
samples remain useful, but exact original timing cannot be claimed now the larger
sources have been removed. Do not use that batch for precise latency or frame-rate
threshold conclusions. Current pilot verification corrects this method.

## Next use

Use high-02 and far-02 as development sequences for visual appearance comparison;
annotate exact bite onset before scoring. Keep the unsuccessful and incomplete
attempts in the session accounting. Native camera restoration is a viable pre-go
candidate, not an implemented or accepted automatic preparation change.
