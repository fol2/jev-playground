# Bounded background click probe

One standalone left-click test against WoW's known character-sheet Lua dialog.
No agent, model request, installer, daemon, Keychain change or foreground activation.
The test opens the character sheet with a process-targeted C key and refuses to
click unless local OCR finds the expected Lua error title. It leaves the character
sheet open afterwards; close it with C before rerunning.

## Source and licence

`NativeWindowServerPreparation.swift` is unmodified; `NativeBackgroundClickTransport.swift`
is a locally adapted copy from
[BackgroundComputerUse](https://github.com/actuallyepic/background-computer-use),
commit `52116acfe0f2f57174f5e0166881abe944cb6eeb`:

- `Sources/BackgroundComputerUse/Actions/Shared/NativeWindowServerPreparation.swift`
- `Sources/BackgroundComputerUse/Actions/Click/NativeBackgroundClickTransport.swift`

The upstream MIT licence is retained in `LICENSE`. `Adapter.swift` supplies the
small DTO bridge. `Probe.swift` is the verification harness. Local transport changes
add right-button event pairs, their correct button/pressure fields, and a move-only
operation, while retaining the audited window routing and no-foreground policy.
The approximately 29 KB source bundle replaces no part of the fishing policy.

The transport uses private Apple window-event symbols. It sends target-only AppKit
input preparation and SkyLight events; it does not call a foreground activation
API. Upstream supports left clicks only. Our right-button extension was verified
by opening WoW's player portrait menu in the background before integration into
the fishing script; it must not be represented as an upstream capability.

## Run from the repository root

```sh
swiftc -parse-as-library -O \
  experiments/001_wow_fishing/probes/background-click/Adapter.swift \
  experiments/001_wow_fishing/probes/background-click/NativeWindowServerPreparation.swift \
  experiments/001_wow_fishing/probes/background-click/NativeBackgroundClickTransport.swift \
  experiments/001_wow_fishing/probes/background-click/Probe.swift \
  -o /tmp/jev-opensource-click-probe
/tmp/jev-opensource-click-probe
# From the normal game view, inspect the player-portrait context menu:
/tmp/jev-opensource-click-probe --right
```

WoW must already be running in the background, using the inspected default UI layout,
with the character sheet closed. Existing Accessibility and Screen Recording grants
are required; this probe does not request or change them. Keep the pointer still
briefly if measuring whether the test moves it. The known close-button coordinate
is proportional to this game's window, not a general UI locator.

Results and two JPEGs are written under `runs/001_wow_fishing/opensource_*/`.
An API success return is insufficient: require the dialog to disappear and inspect
foreground/pointer evidence. The stock upstream sequence includes a target-local
move, an offscreen primer down/up, and the requested target down/up (five events).

## Observed result

`opensource_1789928366`: Lua title present before and absent afterwards, confirmed
by OCR and image inspection. Chrome PID 42672 remained foreground before/after;
the pointer did not move. A concurrent 20-second monitor took 1,647 samples and
observed only Chrome, with zero pointer displacement. Sampling cannot rule out
shorter unobserved transitions. The probe completed in 19.05 seconds including
capture and OCR; this is not click latency. Maximum reported RSS was approximately
115 MiB. Binary size was 165,496 bytes; retained evidence was approximately 1.4 MB.

This original run is useful evidence for background pre-go clicks. It does not establish right
clicks, complete fishing, zero input leakage into another app, other layouts, or
compatibility across macOS releases. This probe alone is not Test A acceptance;
see the parent experiment for the subsequent five-minute result. Test B has not begun.

The later `opensource_1789929898` right-button probe opened the player context menu;
before/after screenshots were inspected, the foreground PID stayed unchanged and
the physical pointer stayed in place. The initial Lua left-click result above must
remain separate from this local-extension evidence.
