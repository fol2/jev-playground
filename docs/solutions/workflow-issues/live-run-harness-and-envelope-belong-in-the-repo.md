---
title: "Keep the live-run harness and envelope in the repo, and make each operator lesson a check"
date: 2026-09-28
category: workflow-issues
module: live-run harness and run envelope
problem_type: workflow_issue
component: development_workflow
severity: high
root_cause: missing_workflow_step
resolution_type: workflow_improvement
applies_when:
  - "A live run is active and a build, rebuild or gate command is about to run beside it"
  - "The live-run harness or its rules (capture, recording, wake, focus) exist only in a session scratchpad"
  - "The run envelope (actions, budgets, expiry, stop and takeover) exists only in the agent's private memory"
  - "A run has ended and the character would stand idle near hostiles before the next one"
  - "A second session, a worktree or another agent is about to run live"
symptoms:
  - "A build beside live run 50 staled frames and it ended WALK_HUD_UNREADABLE; a build ran beside run 95 too, although experiment 001's playbook already forbade it"
  - "The character died idle between runs 56 and 57, and after run 86, before the engine's village walk reached far enough (#72, #101)"
  - "A locked screen held runs 8-9, and a sleeping display stalled the recording probe for 30 minutes before run 96"
  - "Recordings caught a side display with other work on it (runs 49, 75), and a backgrounded recorder ignored SIGINT (run 76)"
  - "A typed /equip left the chat box open and it took the map and walk keys (run 77); Enter would have posted the text publicly"
related_components:
  - live-run-harness
  - run-envelope
  - screen-capture
  - recording-pipeline
tags: [live-run, run-envelope, harness, operator-safety, build-timing, screen-capture, recordings, privacy]
---

# Keep the live-run harness and envelope in the repo, and make each operator lesson a check

## Context

Over live runs 1-100 (25-28 September 2026) the engine's own stops did their job: stale frames, the owner's focus, the run's time and deaths. Some of the failures they stopped on were not caused by the game or the engine. They were caused, or left possible, by what the agent running the runs did around them: a build beside a run, a character left standing among hostiles between runs, a locked or sleeping screen, a recording of the wrong display, a recorder that would not stop, and a chat box left open. No engine code could see these causes. To the engine, a capture starved of CPU looks the same as one that has stalled.

The fixes on the operator's side landed where the next session cannot find them:

- **Two shell scripts in a session scratchpad under /tmp.** `liverun2.sh` wakes the displays, brings Finder to the front, starts a recording and then the `--quests` run. `syncrec.sh` copies a studied recording and its log to the NAS, checks the size there and deletes the local copy. `liverun2.sh`'s comments hold the lessons of runs 49, 75, 76 and 96. The scratchpad belongs to one session, so a new or parallel session cannot run these scripts, or even see them.
- **Private memory notes.** These hold the rules: no builds during a run, no idling in danger, never unlock the screen, and Esc, never Enter. The standing run envelope is there too: area, allowed actions, budgets, stop rules and expiry (auto memory [claude]).

What the tree holds today:

- **The engine's guards.** A quest run reads a frame only if it is at most `FightLimits.maxFrameAge` = 1.0 s old (`experiments/002_wow_visual/m3/Fight.swift:58-59`, applied in `experiments/002_wow_visual/m4/QuestProbe.swift:151` and `experiments/002_wow_visual/m3/FightProbe.swift:98-103`). The limit's own comment assumes 30 fps capture: "an older newest frame is a stall".
  - A walk that cannot read its position ends `WALK_HUD_UNREADABLE` (`experiments/002_wow_visual/m4/Quest.swift:1004-1009`, `experiments/002_wow_visual/m4/QuestProbe.swift:1380`).
  - WoW in front stops a run `OWNER_TOOK_FOCUS`, now through the reflex table's `owner_takeover` entry (controller OWNER; `experiments/002_wow_visual/engine/Controller.swift:105`, #88/#117): `experiments/002_wow_visual/m4/NavProbe.swift:148-150` reads the primitive, `experiments/002_wow_visual/m3/Fight.swift:621-623` and `experiments/002_wow_visual/m4/Quest.swift:1334-1337` act on it.
  - The start refuses to run in five cases (`experiments/002_wow_visual/m1/SeekProbe.swift:161-178`):
    - Screen Recording or Accessibility is not already granted;
    - Escape is held;
    - there is not exactly one WoW process;
    - WoW is in front;
    - there is not exactly one game window. The window is found afresh at each start: owned by the WoW process, layer 0, titled "World of Warcraft", both sides over 300 px.
  - Every frame must come from that window at the session's bounds, 2560x1320 (`experiments/002_wow_visual/m3/FightProbe.swift:98-100`). A quest run with no 2560-wide first frame within `Limits.firstFrameWait` = 2.0 s stops "no 2560-wide frame" (`experiments/002_wow_visual/m4/QuestProbe.swift:1629-1631`, `experiments/002_wow_visual/m0/Motor.swift:51`).
- **The run's end walks to safety.** After #72 and #101, `leaveDanger` walks the character to the nearest Zephras village within `safeReach` = 25 units, errors included (`experiments/002_wow_visual/m4/Quest.swift:843-852`, `:1149-1153`; `experiments/002_wow_visual/m4/QuestProbe.swift:1422-1437` (its owner guard now reads the reflex table's `owner_takeover` entry, #88/#117), called at `:1701`). The walks go in rounds that fight back in between, the combat read now through the reflex table too (`experiments/002_wow_visual/m4/Quest.swift:1116-1147`, #88/#117). #73 resurrects at the Spirit Healer at the run's start and end (`experiments/002_wow_visual/m4/QuestProbe.swift:1680`, `:1702`, `experiments/002_wow_visual/m4/Quest.swift:1042-1044`). Since #96, the opt-in `--quests --session` loop also walks to safety whenever it has nothing to do (`experiments/002_wow_visual/m4/Session.swift:259-264`), and at its end on the same outcomes as a run's end (`:136-138`). An end at the death limit revives and does not walk (`:134-135`). That loop has not yet run live.
- **Typed chat is gone.** #80 removed the typed `/equip NAME` and its chat box (`experiments/002_wow_visual/m4/QuestProbe.swift:1005-1006`, `experiments/002_wow_visual/m4/README.md:1230-1233`). The only Enter left is at the character select screen, and only when the world's minimap does not read and the "Enter World" button does (`experiments/002_wow_visual/m4/QuestProbe.swift:348-357`). The M4c section keeps the typed path as its step 4, now marked as replaced by M4x (`experiments/002_wow_visual/m4/README.md:402-405`).
- **Nothing on the operator's side.**
  - Nothing in the tree checks the screen lock or wakes the displays. `caffeinate` appears only in experiment 001, and nothing anywhere in the repo checks whether the screen is locked.
  - No live-run script or recording harness is in the repo. The m4 README says only that runs were "recorded (the screen, beside the engine, by ffmpeg)" and that recordings "are private and kept off the repository" (`experiments/002_wow_visual/m4/README.md:745-746`). Its live prerequisites are two sentences: the key, the owner's authority, and WoW running but not in front (`:1712-1714`).
  - `docs/agents/ai-sdlc.md:183-189` defines what an envelope must contain, but holds no envelope. The m4 README cites parts of one in passing: Zephras Isle at `experiments/002_wow_visual/m4/README.md:724`, 30 minutes at `:1038`. Some budgets are code defaults that match the standing envelope: the 30 minutes (`experiments/002_wow_visual/m4/Quest.swift:853`) and, since #96, for the session loop one death, 120 graph calls and the second stuck walk (`experiments/002_wow_visual/m4/Session.swift:39-45`, tested at `experiments/002_wow_visual/m4/SessionTests.swift:247-249`). There is still no envelope instance that a harness could read. The area appears only in passing, stop and recovery exist as engine behaviour, and the allowed actions and the expiry are only in private memory.

Experiment 001 did this differently. Its playbook (`experiments/001_wow_fishing/playbook.md`) has "Starting conditions", "Build and run" and "Stop and review" sections. It says "`caffeinate -di`. Run only one controller and do not edit/rebuild it during a trial" (`:52-53`), and its pre-go "stops if the local setup receipt is missing" (`:11-13`). Experiment 002 has no such playbook, and it relearnt these lessons.

Experiment 002 itself started this way. M0 and M1 each wrote their live envelope into their README (`experiments/002_wow_visual/m0/README.md:187-220`, `experiments/002_wow_visual/m1/README.md:140-159`). From M4's `--quests` runs on, the envelope was granted in conversation and kept in private memory, and the m4 README only mentions parts of it in passing.

Sources for the table: the outcomes of runs 50, 57, 77 and 95 come from the private run logs (outcomes only). The locked screen at runs 8-9, the build beside run 95 and run 57's ghost start come from the agent's private memory notes (auto memory [claude]). So do the causes behind runs 50 and 95: a `tools/sdlc check` compile and frames 2-3 s apart at run 50, and a nav-test build with no stale frames at run 95. The 30-minute stall and the recording faults of runs 49, 75 and 76 come from the comments in the scratchpad script, the only record of them.

| Incident (live runs) | Cause | Where the fix lives now | Where it should live |
|---|---|---|---|
| Frames 2-3 s apart, run ended `WALK_HUD_UNREADABLE` (50); a build again beside 95, with no stale frames | `tools/sdlc check` (swiftc) during run 50; a nav-test build during run 95 | Engine: the 1.0 s frame age stopped the run correctly. The rule: private memory | Repo harness: no run starts while a build runs, and no build starts while a run is live |
| Died with no run active: between 56 and 57 (57 started as a ghost), and after 86, 13.6 units from the village | Source-only work while the character stood among hostiles; run 86's end was beyond the 12-unit reach of the time | Engine: #72, #101 (village walk), #73 (Spirit Healer). "Back to back, or end in a village": private memory | Engine parts stay. Repo harness: after a run, report whether it ended `SAFE` in a village, and warn before the character is left elsewhere |
| Runs 8-9 held: "no 2560-wide frame" | The macOS screen was locked | Engine: refuses at start but cannot say why. "Never unlock it": private memory | Repo preflight: check the lock state, and stop naming the owner as the one to act |
| The screen probe waited 30 min (before 96) | A sleeping display | Scratchpad harness: `caffeinate -u -t 5`, then `caffeinate -d -w $$` | Repo harness |
| A side display with other work on it was recorded (49, 75) | avfoundation device numbers change as displays sleep and wake | Scratchpad harness: records only a device probed as 2560 wide | Repo harness |
| The recorder did not stop (76) | ffmpeg started as `a && b &`: a backgrounded subshell that SIGINT does not stop | Scratchpad harness: keeps ffmpeg's own pid | Repo harness |
| The open chat box took the map's key and the walk's (77: `LOG_INCOMPLETE`, `WALK_NO_PROGRESS`) | The typed `/equip NAME` left the box open with letters in it | Engine: typed chat removed (#80). "Esc, never Enter": private memory | Repo preflight and playbook |
| A run with WoW in front reads as the owner taking over | Entering the world leaves WoW in front unless another app is brought forward (auto memory [claude]) | Engine: refuses to start, stops `OWNER_TOOK_FOCUS`. Finder brought forward: scratchpad harness | Repo harness |
| A stale window id after a relaunch | WoW's window id changes on relaunch | Engine: finds the window by process at each start. The agent's own captures: private memory | Repo harness helper |
| #96's session loop needed the standing envelope | The owner granted it in conversation | #96 (merged) took it from a review note. Its budgets are now `SessionLimits` defaults with a test; the allowed actions and expiry are private memory only | A repo envelope that the harness reads (area, actions, budgets, expiry) |

## Guidance

**Treat the machine, the character's position and the harness as part of the run. Keep the harness and its preconditions in the repo, and make each operator lesson a check that runs before, during or after a live run, not a note in a session's memory.**

Split the guards by who can see the cause:

- **Engine guards stay in the engine.** It can see these causes on its own frames, and they worked: the stale-frame stop, the owner-focus stop, the start checks in `wowSession`, the village walk at the run's end, and the Spirit Healer revive. They are SAFETY, RULE and (the owner-focus stop, since #117) OWNER code with tests. Keep extending them there.
- **Operator rules move to a repo harness beside the engine.** The engine cannot see these causes: what else runs on the Mac, whether the screen is locked or asleep, which display is recorded, what the agent does between runs, and whether the envelope is still valid. The harness runs every time, so its checks run every time.

Each lesson as a check:

- **No builds beside a run.** The start refuses while `swiftc` or `tools/sdlc` is running. While a run is live, the harness holds a marker that `tools/sdlc` checks before it builds. The frame-age limit assumes an idle machine, so relaxing the limit is not the fix.
- **No idling in danger.** When a run ends, the harness prints the `leave_danger` outcome and where the character stands. If that is not a village, it says so before anything else starts. The agent then either starts the next run back to back or ends in a village before source-only work.
- **The screen.** The start checks the lock state and stops with "screen locked: the owner's to unlock"; it never unlocks. The harness wakes the displays and keeps them awake for the run's life.
- **The recording.**
  - Record only a device probed as 2560 wide now, never a default or a remembered number.
  - Keep the recorder's own pid, and stop it by that pid.
  - Recordings show other players' names. They stay under the ignored `runs/` (or `data/`, per `experiments/README.md:25`, `:34`) and on the NAS, never in the repo. The sync keeps the NAS's details in the operator's local ssh configuration, not in the script.
- **The chat box.** If an edit box is open, press Esc, never Enter: Enter sends what was typed to other players. If a preflight finds a chat box open, it stops, or presses Esc, before any movement key.
- **Focus and window.** The harness brings another app to the front before the run, and finds WoW's window by its process every time, never by a saved id.
- **The envelope.** Keep one checked-in envelope instance: area, allowed actions, budgets, stop rules, recovery and expiry, in the terms of `docs/agents/ai-sdlc.md:183-189`. The harness reads it and refuses after the expiry. It holds no character name, credentials or host details.

Working rules:

- A lesson is finished when its check exists. After a run lost on the operator's side, the fix adds a harness check, just as an engine failure adds a regression (AGENTS.md: "add a regression").
- Side tools may be shell, as `tools/sdlc` is. Engine code stays Swift. The harness starts the engine and never changes what it decides.
- Keep the harness small: one start script, its checks, the envelope file and a playbook section like experiment 001's. It is not a new subsystem.
- A stop caused by the operator is not an engine failure. Record the machine's state beside the run so that the outcome is not blamed on perception.

## Why This Matters

- **Wall time.** Runs 8 and 9 were held on a locked screen. A sleeping display cost 30 minutes before run 96. Run 50 was lost to a build. The death between runs 56 and 57 paused live runs under the one-death stop, and run 57 started as a ghost (auto memory [claude]).
- **Accurate outcomes.** Run 50's `WALK_HUD_UNREADABLE` reads like a perception failure, but the cause was a compiler beside the run. The engine-capability learning asks for an accurate log, and a log is only accurate if the machine's state is recorded beside it.
- **Recurrence.** The no-rebuild rule was already in experiment 001's playbook (`experiments/001_wow_fishing/playbook.md:53`), and experiment 002 learnt it again at run 50. After the memory note was written, a build still ran beside run 95. Run 75 repeated run 49's wrong display. A note works only when a session thinks to look for it. A check runs every time.
- **Other sessions.** PR #96's description says its session loop took its defaults from the owner's standing envelope through a review note (commit 6). A parallel session or a worktree has no other way to know the envelope, and cannot run the scratchpad harness at all. On 28 September the session taking over #96 found the harness only by listing other sessions' scratchpad folders, copied `liverun2.sh` into its own scratchpad and adapted it. A worktree also has neither `runs/` nor `.env`, so it linked the main checkout's `runs/` in by hand (session history). A repo harness should take the evidence and environment paths as parameters.
- **Drift nobody reviews.** When this note was written, the only envelope instance, in private memory, had drifted from the code (auto memory [claude]):
  - it still allows the chat box for "`/equip`-type slash commands", which #80 removed;
  - it keeps walks within 12 units, while a run's end now walks up to 25 (#101).

  The note was then corrected by hand. A repo file changes in a PR, where a reviewer can compare it with the code.
- **Privacy.** Runs 49 and 75 recorded a display with other work on it. Only the probe for the 2560-wide device prevents that, and today it is in a script that the next session will not have.

## When to Apply

- Before any live run starts, and before any build, test or long source-only stretch while the game is running.
- When a run stops for a cause outside the game: stale frames, no frame, `OWNER_TOOK_FOCUS` with no owner at the keys, or a recording of the wrong screen.
- When a lesson is about to go into a memory note or a script comment in a scratchpad. Put it in the repo as a check instead.
- When a second session, a worktree or another agent will run live, as with #96's session loop.
- When the owner grants, widens or renews the envelope. Change the repo instance in a PR.

Exception: the owner's stop and the engine's safety stops act at once. Add the harness check afterwards.

## Examples

**Run 50 (a build beside a run).**
- *Before:* `tools/sdlc check` ran during the run. Frames came 2-3 s apart, past the 1.0 s limit. The run ended `WALK_HUD_UNREADABLE`. The engine was right to stop, and the fault was the operator's. The rule went into a memory note, and a build still ran beside run 95.
- *After:* the harness refuses to start a run while a build runs, and `tools/sdlc` refuses to build while a run is live.

**Between runs 56 and 57, and after run 86 (idle in danger).**
- *Before:* source-only work while the character stood among level 2-3 hostiles. It died, and run 57 started as a ghost (auto memory [claude]). The engine then got the village walk (#72), the Spirit Healer (#73) and a 25-unit reach (#101). After run 86 had ended 13.6 units from Thendal Village, the character died where it stood before the next run (`experiments/002_wow_visual/m4/Quest.swift:849-850`).
- *After:* the engine parts stay. The harness also reports each run's end position and `leave_danger` outcome, so the next step is either another run or a walk to a village.

**Runs 8-9 and 96 (the screen).**
- *Before:* the locked screen gave "no 2560-wide frame", and only a manual `ioreg` showed the lock (auto memory [claude]). A sleeping display stalled the recording's probe for 30 minutes. The fixes went into the scratchpad script's `caffeinate` lines and a memory note: "never unlock it".
- *After:* a preflight names the lock and stops, and the harness wakes the displays and keeps them awake for the run's life.

**Runs 49, 75 and 76 (the recording).**
- *Before:* a default or remembered avfoundation device recorded a side display. `a && b &` left a recorder that SIGINT did not stop.
- *After:* the fixes are the scratchpad script's lines (probe for the 2560-wide device, keep ffmpeg's pid), moved into the repo harness. Recordings stay private under the ignored paths and on the NAS.

**Run 77 (the chat box).**
- *Before:* a typed `/equip NAME` left the chat box open with letters in it. The box took the map's key (`LOG_INCOMPLETE`) and the walk's (`WALK_NO_PROGRESS`). #80 removed typed chat from the engine. "Esc, never Enter" stayed in memory, and it matters most when the agent takes direct control.
- *After:* the rule is in the repo playbook, and a preflight finds an open chat box before the first movement key.

## Related

- `docs/solutions/architecture-patterns/fix-engine-capability-not-goal-patches.md`: the engine side of the same runs. That note fixes the capability, not the per-run patch. This one puts operator lessons in repo checks, not in memory.
- `AGENTS.md`: "Scripts own capture timing, measurement, admissibility, key execution, watchdogs, budgets and emergency stops", and "Live authority must identify machine/account, permitted actions, privacy scope, call/time/loss budgets, expiry, stop/takeover and recovery".
- `docs/agents/ai-sdlc.md:181-189`: what a run envelope contains, and "Consent to source changes is not a live envelope".
- `experiments/001_wow_fishing/playbook.md`: the earlier experiment's operating rules, kept in the repo.
- `experiments/README.md:25-34`: raw recordings stay local and are not committed.
- PR #96 (merged 28 September): its session loop's envelope defaults came from a review note (commit 6), and are now `SessionLimits` in `experiments/002_wow_visual/m4/Session.swift`.
- PRs #72, #73, #80 and #101: the engine-side fixes named above.
- Issues:
  - #87 (the session loop, opt-in since #96 and not yet run live): its idle-safe mode walks the character to safety when the session has nothing to do. Between separate runs the harness still has to check.
  - #88 (the reflex table, `ReflexTable.standard` in `experiments/002_wow_visual/engine/Controller.swift`): its `owner_takeover` entry (controller OWNER) merged in #117 and now runs the owner-focus check that used to be inline at each stop; #88 itself stays open pending live qualification. The harness brings another app to the front but does not detect the takeover itself.
  - #93 (run reports): a natural place for the harness's operator events, such as a build during a run, a locked screen or a wrong display.
