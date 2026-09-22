# 002 — Screen evidence for a Shaman decision experiment

Status: **offline contract skeleton, not a visual interpreter or game-playing agent**.
The current client family/build, level, specialisation, abilities and UI calibration
are unverified. No new dependency, service, database, model call or input executor.

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

Only the packet validation is implemented here. `observations.policy_state` checks
schema, stream and geometry identity, a caller-supplied freshness deadline, bounded
values and source ROIs. It preserves `unknown` instead of inventing false/zero and
returns a detached copy. Coordinates are capture pixels, not desktop click points.
All times use one monotonic clock. Renew `stream_id` on a new capture session and
`geometry_id` on window/scale/calibration changes; those changes are detected by a
future adapter, not by this stateless function. The future consumer must also reject
reordered frames and bind every proposal to its originating frame and target.

An `observed` measurement is not proof that its interpretation is correct. A tracked
patch may not be a bobber; correlation is not identity/bite confidence. Field-specific
extraction, semantic validation and calibration still require labelled screenshots.
Pixels, OCR and motion are the only methods admitted by this prototype. Audio is a
later, separately authorised and timestamped observation source, not implemented here.
No hidden game state, memory reading, packet parsing or injected telemetry is used.

## Reproduce offline

```sh
python3 -S -m unittest discover -s experiments/002_wow_visual -p 'test_*.py' -v
```

`test_observations.py` contains synthetic packets: schema/identity failures, future
and expired frames, ROI bounds, invalid numerics, unknown versus false and size limits.
They demonstrate the interface, not HUD-reading accuracy. The existing Focus Gate
selects these tests for this experiment and still rejects unknown executable paths.

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

Primary sources checked 21 September 2026. No real-game results are claimed here.
