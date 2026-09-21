# Test B: Jev bite decisions

Use the [shared playbook](playbook.md) for setup, input, stopping and acceptance.
The current protocol is `anchored-pixel-bite-only-v1`, not the earlier expanded
preparation-and-fishing experiment. Historical findings remain unchanged.

## Run

Keep `TYPESAFE_API_KEY` in the ignored local `.env` or environment, never Git:

```sh
sh experiments/001_wow_fishing/build.sh
caffeinate -di python3 experiments/001_wow_fishing/run_test_a.py --background --jev
```

This is a live-input command, not an offline check. Only one controller may run.
The shared runner performs one deterministic preparation with zero provider calls,
then applies Jev's bite policy. Results are under `runs/001_wow_fishing/test_b_*`.
There is no automatic rules fallback after a provider error.

## Observation contract

Jev receives seven chronological `[seconds since first sample, dx pixels, downward
dy pixels, match correlation]` rows and background brightness change. Displacements
are relative to the median of the first four rows. Times come from capture, not
an assumed 10 Hz interval. Correlation means appearance agreement, not submersion
or bite probability. No screenshots, audio, tooltip OCR, static-area ratios,
duplicate motion narrative or Test A verdict are sent. Short recovery windows formed
after a supported bite dropout are never submitted because requests are gated while
the loop is armed.

Both policies use the same fixed-anchor matcher and recovery state machine. A
gap invalidates history, request generation and pending action together. A late
cancelled callback cannot occupy a newer request's slot. Strong background change
stops the run; it does not trigger speculative reacquisition or a fresh cast.
The matcher rejects ambiguous peaks and +/-12-pixel boundary peaks. Larger motion,
occlusion or changed appearance may stop it. This does not eliminate all possible
water/float confusion; see [refactor notes](refactor-notes.md).

## Limits and logging

The model remains pinned to `jev-1.13.0`, using native URLSession HTTPS. At most
120 attempted calls are allowed across the run, one in flight at a time. Requests
occur on broad observed changes or every four seconds while quiet, at least 0.2
seconds apart. This scheduler is independent of A's verdict but limits what B sees.

Request timeout and response age limit are 1.5 seconds. There are no application
retries. A REEL probability below 0.85 abstains; that retained pilot threshold is
not an empirical success probability. REEL must reference the same uninterrupted
observation generation and still waits for two distinct fresh recovered frames.
The two-second recovery deadline starts at the triggering observation, so network
time consumes the action allowance. The click permission is consumed once.

`policy_observation` links call ID, capture time and generation. `jev_request`
records the exact question/state; `jev_response` records output, probabilities,
confidence, model, reported usage and round-trip time. No API key is logged.
Cancelled/failed requests may consume provider usage that is never returned, so
summed tokens are not a billing guarantee. Local JPEGs stay under ignored `runs/`.

## What can be compared

Preparation, capture, input and loot verification are now shared, isolating the
bite-policy difference. Earlier B runs changed preparation too and used different
visual features; do not pool their scores or token totals with this version.
Live casts still differ stochastically: this is not a paired/randomised benchmark.

Apply A's strict five-minute acceptance, except B must contain actual provider
requests and supported REEL choices. Keep the shared pre-go result, every failed
cast, starting-view evidence and source hashes. Collection is still visual, with
optional item labels and no inventory queries. Offline tests and historical
perfect runs do not establish acceptance of this candidate.
