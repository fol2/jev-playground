# Shared operating playbook / Test A

This candidate has offline regression coverage, not fresh live acceptance.
Test A uses no model calls. Test B changes only the bite policy; see its
[playbook](test-b-playbook.md). Historical successes belong to their recorded source.

## Starting conditions

Use the tested Mac with Swift and Python 3. Screen Recording and Accessibility
permissions must already be granted to the executing environment. Handle permission
dialogues manually; this experiment does not install services or change Keychain.

Use the tested default UI and combined bags. The calibrated trial window was
2560 x 1440; other sizes, UI scales and layouts are not accepted automatically.
Keep the camera, character heading and window unchanged. The float must land in
the upper playfield, clear of the avatar and HUD. Acquisition covers window
x 0.02–0.85, y 0.08–0.55, with the central avatar region excluded.

For a full preparation transition, start with the normal main weapon and action-bar
page 1. Keep Fishing in slot 1 of page 2, bound to physical key `1`. The rod must be
in the visible default combined bag: ten columns by five rows are searched with
icon matching and tooltip confirmation. Other icons/layouts may require calibration.
Leave room for loot and leave the existing auto-loot setting unchanged. Close bags,
character sheet, chat entry, menus and loot windows. Resolve beta refresh notices.

`--background` uses targeted input without activating WoW. Keep the window available,
not minimised. Voluntarily watching it in the foreground is allowed and logged.
The explicit foreground route requires existing focus; it never activates the app.

## Build and run

Run the offline checks in the [README](README.md) first. For a separately authorised
live trial, from the repository root:

```sh
sh experiments/001_wow_fishing/build.sh
python3 experiments/001_wow_fishing/run_test_a.py --background
```

The build writes `/tmp/jev-fishing-live` and runs native offline checks. Rebuild
after source changes or removal of that binary. Keep the checkout available for
reference images. To keep the Mac awake, prefix the Python command with
`caffeinate -di`. Run only one controller and do not edit/rebuild it during a trial.

Pre-go runs once: verify/equip the rod, handle the known beta character dialogue,
select page 2 and verify Fishing in slot 1. Its timeout is 120 seconds. Each
subsequent cast verifies the Fishing progress bar and requires a visible float
within six seconds. Do not invoke internal `--prepared` yourself.

The autonomous interval starts after preparation and lasts 300 seconds plus any
in-flight cast (normally no more than 345 seconds). Foreground fallback is a
separate full trial with restored starting state: omit `--background`; never
splice its results into a failed background interval.

## Stop and review

Ctrl-C in the runner terminal is the primary stop; the native helper also checks
Escape. Any native `stopped_*` event, uncertain loot or child timeout stops the run
for review. Ordinary non-terminal timeouts stop after three consecutive failures.
Camera/background change now stops rather than recasting or changing heading.

The script does not restore the original weapon/page. Inspect remaining overlays
before a new trial. Review acquisition and first-missing images after target loss;
do not blindly lower thresholds. For `stopped_bite_not_recovered`, inspect the
two-second return window. For uncertain loot, inspect before/after UI images and
actual bag capacity. An unreadable item name alone is not collection failure.

Output lives under `runs/001_wow_fishing/test_a_<UTC>_<id>/`. Inspect `summary.json`,
`pre-go.log`, every `cycle-NN.log`, and each cycle's referenced `live_*` evidence.
A strict pass requires a completed interval of at least 300 seconds, exactly one
pre-go, every recorded cycle verified by a loot-window transition, no gameplay
intervention, zero provider calls in A and `perfect_run: true`. Successful process
exit alone is insufficient. Failed casts must never be excluded.

`mode: background` means all observed focus states were background;
`targeted_mixed_focus` means WoW was foreground at least once. Neither infers
unobserved focus. `loot_clicks` counts attempts, not inventory quantity. Collection
may be automatic with empty label metadata; no name/language whitelist is used.

Compare recorded source hashes after a trial. Historical `verification.json` files
were produced separately, not automatically by the runner. Preserve failed evidence
and its source version; remove old ignored recordings/results only deliberately.
No single perfect run establishes general reliability.
