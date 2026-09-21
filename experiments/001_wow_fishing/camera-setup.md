# One-time camera setup

Camera configuration is separate from preparation and fishing. Choose a clear-water
pitch and zoom once, then save that baseline. Pre-go now restores it with
**Control+Option+F9** on each trial; it must not rebind keys or save the current
camera. This script owns assigning, binding and saving, and is not run per trial.

From the repository root:

```sh
sh experiments/001_wow_fishing/setup_camera.sh --help
sh experiments/001_wow_fishing/setup_camera.sh --execute --save-current-view
```

Use the existing Mac permissions, a logged-in character and the default settings
layout. Close bags, chat and dialogues first. Keep the window available and leave
input alone during setup. The script targets WoW without activating it. It opens
native Options → Key Bindings, finds the view rows using local OCR, assigns
Control+Option+F9 to Set View 1 and Control+Option+F10 to Save View 1, reads both
bindings back, closes the menu and sends the save key. It never casts, equips,
turns the character, runs in-game Lua or calls Jev.

Reserve these two shortcuts for the experiment. Native assignment may replace
another action using the same shortcut. Existing different bindings on the two
view rows cause a stop. The currently selected account/character binding scope is
preserved. An unreadable page, changed window, Escape or 90-second deadline stops
setup; completed UI changes are not rolled back automatically. Inspect the native
settings before retrying a partial run.

The script saves the **current** pitch and distance, not a universal camera angle
or a character position/heading. After setup, change camera pitch/zoom without moving
the character and press Control+Option+F9 to verify restoration. A local receipt in
`data/001_wow_fishing/camera-setup.json` distinguishes binding readback and save-key
submission from visual verification. It is not a readiness certificate for another
character, client or display configuration. Re-running refuses to overwrite the
receipt unless `--replace` is explicitly supplied; that also saves a new baseline.

Setup exits when finished, retains no screenshots/video and makes no model requests.
The disposable compiled executable is removed on exit. There is no recurring setup
cost during A/B trials. Local OCR supports English and Traditional Chinese labels;
its scrollbar offset assumes the native default settings layout. Other languages,
UI scales, window modes and restart persistence are not yet live-verified.

## Verification on 21 September 2026

On the current Forever beta, Traditional Chinese UI, 2560 × 1440 window:

- Both experiment shortcuts were cleared using the native UI. Standalone setup
  assigned both again and verified their displayed modifiers and function keys.
- Setup closed the settings and game menu without casting or changing position.
- A camera-only left drag and zoom-out changed the view. Control+Option+F9 restored
  the saved water framing and avatar scale, checked in before/after screenshots.
- A second run saved a visibly different clear-water pitch; after another camera
  disturbance, restoration returned to that new baseline, proving a new save rather
  than merely recalling the old preset.
- This is camera-setup evidence, not fishing accuracy or full A/B acceptance.

Offline checks (no running game or permissions required):

```sh
sh experiments/001_wow_fishing/setup_camera.sh --self-test
```

These cover label identity, matching the correct binding column/row, and rejecting
incomplete or different shortcuts. The live checks above provide the actual native
UI and preset proof; synthetic OCR rows do not establish general visual accuracy.
