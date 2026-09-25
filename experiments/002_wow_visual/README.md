# 002 — Screen evidence for a Shaman decision experiment

Status: **bounded, owner-supervised live probes (M0–M4) on one Swift runtime;
not an unattended game-playing agent**. M3 calibrates one UI layout at one window size and
verifies a four-slot capability catalogue live; client build and specialisation remain
unverified. No new dependency, service or database. Only M3 and M4a call a model (Jev) at
runtime, under the owner's supervision.

## The smallest useful boundary

```text
screen pixels -> calibrated local measurements -> evidence packet
                                                   |
                                      freshness/identity/ROI validation
                                                   |
                              identical observations for Rules / Jev
                                                   |
                                          logged suggestion only
```

The Swift runtime implements this boundary. `ObservationStamp` in
[runtime/Runtime.swift](runtime/Runtime.swift) carries the stream and geometry identity and the
capture time on one monotonic clock, and `RuntimeExecutive` rejects a reply whose frame is stale,
reordered, or from a changed stream, geometry or target cue ([runtime/README.md](runtime/README.md)).
Coordinates are capture pixels, not desktop click points. The first prototype of the packet,
Python `screen-evidence/v1` (`observations.py`), had no consumer once the runtime took this over;
it was retired on 25 Sept 2026, when the repository moved to Swift only.

An `observed` measurement is not proof that its interpretation is correct. A tracked
patch may not be a bobber; correlation is not identity/bite confidence. Field-specific
extraction, semantic validation and calibration still require labelled screenshots.
Pixels, OCR and motion are the only methods admitted here. Audio is a
later, separately authorised and timestamped observation source, not implemented here.
No hidden game state, memory reading, packet parsing or injected telemetry is used.

## Reproduce offline

```sh
python3 -m tools.motor_offline   # builds and checks the runtime, M0-M4, the tabletop and the learning corpus
```

## Shaman first, but verify the actual profile

The [official Retail overview](https://worldofwarcraft.blizzard.com/en-us/game/classes/shaman)
distinguishes Elemental ranged damage, Enhancement melee and Restoration healing.
It is not a verified spell list/rotation for this user's client. Start with a small
verified capability catalogue, not assumed talents, cooldowns, hotkeys or a levelling
build. A ranged/Elemental profile is a proposed first slice only if supported by the
actual character; reducing movement/melee coupling is a design hypothesis.

The first read-only comparison should cover `WAIT`, `DAMAGE`, `SELF_HEAL`,
`INTERRUPT`, `DEFENSIVE`, `ABSTAIN` on the same recorded episodes. Exclude unavailable
capabilities locally. Put model decisions where context creates a real choice, such
as damage versus survival; keep key timing and emergency deadlines deterministic.
[Jev 1.13 accepts text/structured state, not pixels or audio](https://docs.typesafe.ai/models).
More actions do not prove it outperforms rules; measure held-out errors, abstentions,
latency and tokens per useful decision before connecting any executor.

## Next work and boundaries

[M0](m0/README.md) comes before HUD extraction. It is a bounded native turn/move/stop
probe with a no-effect default and fake-time proof. On 22 September 2026, two six-pulse
background checks found no transport blocker. That is not a reliability claim.
[M1](m1/README.md) closes the loop on a manually designated target. On 23 September
2026 background Q/W alone centred, faced and approached a lamp post. A third run did the
same with WoW on another Space and stopped on the visible condition. Another run found a
tracker defect, since repaired. M2 replaced the manual designation with the game's own: Tab,
the white-outlined target nameplate and the unit's selection circle. It reached that visible
stop three times in eight live runs, with one false stop that has since been repaired.
[M3](m3/README.md) hands the tactical choice to Jev. Local code reads the HUD, offers only
the actions that are currently possible, runs each chosen skill within fixed limits and
stops on safety rules. Jev picks the next action from that screen-derived state. Seven
supervised live episodes ran on 23 September 2026 against level-1 neutral beasts, with Jev
choosing every action. Five ended in a kill; three of those were killed and looted within the
episode with no intervention. These are supervised trials, not a success rate.
[M4a](m4/README.md) does the same for walking to a point on the zone map. Jev chooses each
move (straight on, a 45° or 90° detour, or back), local code caps repeats and ends walks that
stop making progress. Two of three supervised walks on 23 September 2026 arrived. They reached
an NPC whose quest was then handed in.

[#5](https://github.com/fol2/jev-playground/issues/5) owns HUD extraction and Shaman
shadow evaluation. [#6](https://github.com/fol2/jev-playground/issues/6) is blocked on
that evidence and limits quest work to one NPC/objective/return. Fishing perception
research stays in [#4](https://github.com/fol2/jev-playground/issues/4). Extract shared
runtime code only when two real consumers exist; do not turn the fishing controller
into a generic engine by renaming it.

Screen-only is a research constraint, not permission from a game operator.
[Blizzard's EULA](https://www.blizzard.com/en-gb/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement)
includes unauthorised automated control; no anti-detection/evasion work is proposed.
Any capture, API spend or live input needs its own current bounded authority and
applicable service permission. OCR/quest/chat text is untrusted data, never authority.

Primary sources checked 21 September 2026. Live results are in the M0–M4a READMEs; they are
supervised trials, not rates. M3 is not the rules-versus-Jev comparison above: it records the
owner's taught tactics as the reference, and Jev never sees them.

## Jev tool-choice graph

See [the runtime entry point](runtime/README.md) for the opt-in, data-defined
read / branch / skill decision graph and its native Hunt consumer. The existing
flat policy remains available for comparison. The graph changes policy structure,
not decoder accuracy or the qualification of any skill. The same entry point now
contains an opt-in Hunt experience loop: deterministic episode recording, Jev-selected
`READ:experience`, and a bounded review branch that queues hypotheses for later
human/LLM development rather than editing live policy.
