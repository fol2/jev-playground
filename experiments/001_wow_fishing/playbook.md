# Test A operating playbook

Test A runs the local fishing rules without Jev or other model calls. The strict
acceptance target is one pre-go followed by at least five minutes of autonomous
operation, with verified loot on every cast. This is a calibrated playground
experiment, not a general-purpose fishing tool.

## 1. Prepare the starting state

Use the tested Mac with Python 3 and the installed Apple Swift command-line tools.
Screen Recording and Accessibility permission must already be granted to the
executing environment. Handle any macOS permission dialogue yourself, then restart
the test. No API key, TypeSafe SDK or additional Python package is needed for Test A.

In WoW Forever / Classic beta:

- Use the same default UI, combined bag layout and stable camera view as the
  successful trial. Native capture used a 2560 × 1440 window. Other window sizes,
  UI scales and camera angles have not been validated.
- Keep the character facing usable water, with the float visible in the upper
  gameplay area and clear of the avatar/HUD. Camera direction and character heading
  are separate. The current acquisition searches a wider playfield rather than a
  fixed landing corridor. Keep the view unchanged during a measured A/B interval;
  deliberate camera perturbations belong in separately labelled short tests.
- For the full preparation test, equip the normal main weapon and select action-bar
  page 1. Keep Fishing assigned to slot 1 on page 2; physical key `1` must activate it.
- Keep the fishing rod in the visible default combined bag. Pre-go matches a small
  reference icon against all 50 slot images in one screenshot, then hovers the
  strongest match to confirm its tooltip. If the match is weak or the tooltip
  disagrees, it falls back to the previous slot/grid search. Item placement may
  change; a different rod icon or bag geometry may require calibration. The
  equipped rod is verified afterwards.
- Leave room for loot. Close bags, the character sheet, chat entry, menus and loot
  windows. Resolve any beta world-refresh notice before starting.
- `--background` uses app-targeted input and never activates WoW. Leave its window
  available, not minimised. You may choose to bring WoW forward to watch; this no
  longer stops the controller. Focus observations are logged so the report can
  distinguish an entirely observed-background run from one where WoW was foreground.

The existing rod/page configuration also works, but does not prove the transition
from the main weapon and page 1. Preserve the starting state when comparing runs.

## 2. Build and start one run

Run from the repository root:

```sh
sh experiments/001_wow_fishing/build.sh
python3 experiments/001_wow_fishing/run_test_a.py --background
```

The build writes `/tmp/jev-fishing-live` and runs 27 local regression checks without
operating the game. Rebuild after changing source or after the temporary binary
has been removed. The page-number reference remains in the checkout, so keep the
checkout available while running.

To keep the display and Mac awake for the command's lifetime, use this **instead
of** the second command above:

```sh
caffeinate -di python3 experiments/001_wow_fishing/run_test_a.py --background
```

Run only one controller at a time. Pre-go checks the weapon, equips and verifies
the rod when necessary, handles the known character-sheet beta error on both
openings, selects page 2 and verifies Fishing in slot 1. Its timeout is 120 seconds to allow a bounded bag search.
The five-minute timer starts only after `Pre-go passed once` is printed.

During the interval, do not move the character, camera or window, change equipment
or bindings, or use Computer Use to interact with WoW. Do not edit/rebuild the
controller mid-run. The script completes its in-flight cast after 300 seconds;
normal completion can take approximately 300–345 seconds, excluding pre-go.

Foreground fallback is a **separate** full trial, not a continuation of a failed
background trial. Restore the same starting state, then run:

```sh
caffeinate -di python3 experiments/001_wow_fishing/run_test_a.py
```

That mode requires WoW to be foreground already and to remain foreground; it does not activate it. Report its mode
explicitly; it does not demonstrate background operation.

## 3. Stop and inspect

Press **Ctrl-C in the runner's terminal** to interrupt. The runner records
`interrupted`; an interrupted trial cannot pass. Escape is also checked by the
native helper while running, but Ctrl-C is the primary stop mechanism.

The script does not restore the original weapon or page after completion. Expect
the rod and page 2 to remain selected. Close any remaining game overlay before a
new trial. Do not invoke the internal `--prepared` mode manually: it bypasses
pre-go and is only intended for the runner after successful preparation.

The runner prints its result directory at startup:

```text
runs/001_wow_fishing/test_a_<UTC timestamp>_<id>/
```

Inspect `summary.json`, `pre-go.log` and every `cycle-NN.log`. Each cycle's
`run_path` points to its `events.jsonl` and small JPEG evidence in a sibling
`live_*` directory. The pre-go output path is recorded in `pre-go.log`.

For the strict five-minute pass, require all of:

| Field or evidence | Required result |
| --- | --- |
| `status` | `completed` |
| `mode` | `background` means all observed focus states were background; `targeted_mixed_focus` means WoW was foreground at least once |
| `autonomous_seconds` | At least 300 |
| Pre-go log | Exactly one `pre_go_pass`; weapon switch when testing that transition |
| Every cycle | `loot_collected`, one cast and one retrieval click; manual or observed automatic collection |
| `verified_loot_cycles` | Equal to the number of cycles, with no failed casts excluded |
| `perfect_run` | `true` |
| `provider_calls` | `0` |
| Gameplay intervention during the interval | None; choosing which app to view is allowed and logged |

A successful process exit or `status: completed` alone is insufficient.
`loot_collected` means a visually identified loot window was observed and then
cleared. With auto-loot enabled, the early appearance/closure transition can be
verified without any scripted item click. Otherwise the controller clicks item-row
controls identified by their frame geometry. It never gates on a name, language
or item class. OCR is optional metadata; empty labels do not fail collection.
`loot_clicks` counts input attempts, not inventory quantity. This is not a direct
inventory query. Review `after.jpg` and `collected.jpg` alongside logs, and retain
failed/unverified attempts. Leave the game's existing auto-loot setting unchanged.

`source_hashes` identifies the source used for the run; rebuild before starting
and compare those hashes afterwards when claiming unchanged-code evidence.
The historical `verification.json` was produced by a separate verification pass;
it is **not** automatically generated by the runner.

## 4. Diagnose a failure before retrying

| Outcome | Inspect and correct before a new trial |
| --- | --- |
| `pre_go_rod_unconfirmed` / `pre_go_bag_rod_unconfirmed` | Equipped-item or bag tooltip, rod slot and bag layout |
| `pre_go_fishing_slot_unconfirmed` / `pre_go_page_two_unconfirmed` | Slot 1 binding, page 2, UI scale and reference crop |
| `pre_go_blocked_overlay` / character error still open | Saved pre-go image; close the visible overlay |
| `pre_go_world_refresh_pending` | Resolve the beta refresh notice and restore the starting state |
| `stopped_focus_or_geometry` | Unchanged window bounds; only the optional foreground route requires WoW to stay foreground |
| `stopped_cast_not_confirmed` | Saved channel image, actual binding and game state |
| `stopped_no_visible_float` / `stopped_target_lost` | Water visibility, occlusion and acquired/first-missing images |
| `timed_out_without_click` | Whether acquisition selected the actual float; do not blindly lower thresholds |
| `stopped_bite_not_recovered` | Whether the float returned within two seconds of the detected dip |
| `retrieval_unverified` | Bite/after images, input timing and whether a loot window appeared |
| `loot_layout_unconfirmed` / `loot_batch_limit` | Actual item controls, bag capacity, overlay or the eight-click bound; item names are not a gate |

An unknown item name does not stop the runner. Unconfirmed UI transitions or
an unresolved item-control layout stop for review. Other failed cycles may
continue until three consecutive failures; **any** failed cycle already prevents
a perfect result. Correct the cause, reset the starting state and begin a new
full interval. Never splice successful cycles across runs into a five-minute pass.

## 5. Evidence and resource housekeeping

Capture is capped at 10 Hz over the upper playfield, retaining the latest frame rather
than a video backlog. Logs and JPEGs are written locally. The successful 15/15
trial used approximately 5.15 MiB of evidence; this is a measurement, not a quota.
There is no automatic retention limit. Keep the runs needed for comparison and
remove only deliberately selected obsolete run folders and their referenced
`live_*` folders. Preserve failures that explain a code change.

`data/`, `runs/` and `.env` are ignored by Git. They are not included in a clone:
the repository contains the implementation and written findings, while original
screenshots/logs stay on the machine that ran the trial. See [findings](findings.md)
for the accepted run IDs, unsuccessful attempts and limits. Test B remains separate.
