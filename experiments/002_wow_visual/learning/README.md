# Learning from human play (video, research, knowledge base)

Offline evidence for how Jev should play like a skilled human (first class: Shaman, levels 1-10).
None of it touches the game. All results below are **offline replays of recorded video**, not live play.

## What was done (23-24 Sept 2026)

1. **Research.** Six Cursor (Composer 2.5) agents read websites and video subtitles with one shared brief
   ([research/common.md](research/common.md)). They produced [shaman_class](research/shaman_class.md),
   [leveling_fundamentals](research/leveling_fundamentals.md), [zephras_walkthrough](research/zephras_walkthrough.md),
   [videos_low](research/videos_low.md), [videos_mid](research/videos_mid.md) and
   [multiclass_framework](research/multiclass_framework.md).
2. **Knowledge base.** Grok 4.7 merged the research into [knowledge/general.md](knowledge/general.md), which holds
   119 class-agnostic facts. It also produced [knowledge/shaman.md](knowledge/shaman.md), which holds a class
   schema with the Shaman facts; other classes fill the same schema. Every fact carries a trust tag and a source.
   [knowledge/conflicts.md](knowledge/conflicts.md) lists 22 disagreements between sources.
3. **Video frames, not only subtitles.** Two public videos by Zerocks were analysed frame by frame:
   - *Skyborne Shaman: Zephras Isle, WoW Forever Beta Launch Day, No Commentary #1* (YouTube `hCXWhb2_CyQ`,
     30 min, level 1 up). Frames were taken at 1 fps and tiled 3×2 into 300 sheets. Grok 4.7 read every sheet,
     following [zerocks1/brief.md](zerocks1/brief.md). For each part of the video it wrote the techniques
     (`partN_techniques.md`) and the decision points (`partN_decisions.jsonl`, 236 in total). Each decision point
     records the state, three options and the option the human took, with evidence.
   - Episode #4, read at one frame every 5 s: [zerocks4_frames.md](zerocks4_frames.md).
   - A caption-only pass over longer streams: [stream_captions_techniques.md](stream_captions_techniques.md).
     Some timestamps in it are invalid (for example "0:88:00"), so treat it as low trust.
4. **Jev against the human.** [video_jev.py](video_jev.py) puts each decision point to live Jev (`jev-1.13.0`)
   with the goal and a set of facts, then compares Jev's pick with the human's. Mismatches are in `zerocks1/runs/`.

## Results (offline replay against live Jev)

| Part | Hand-written facts | Knowledge base (`KB=1`) |
|---|---|---|
| 1 (93 points) | 67/93 | 65/93 |
| 2 (75 points) | 48/75 | 48/75 |
| 3 (68 points) | 36/68 | 40/68 |
| Total | 151/236 (64%) | 153/236 (65%) |

The hand-written facts for part 1 include the regeneration fact.

- **One targeted fact beats many facts.** Adding "at levels 1-5 health and mana refill in 10-20 s while walking"
  changed 4 of the 5 "drink or keep going" misses ([zerocks1/regen_probe.jsonl](zerocks1/regen_probe.jsonl)).
  Swapping in the whole knowledge base (184 facts) moved the total by only +2.
- **About 30-40% of misses are noise.** They are UI moments (menus, the guild window, vendors, error dialogs) or
  launch-day habits of the streamer. They are not tactics worth copying.
- **Real themes in the misses.** The human does these things; Jev did not:
  - skips mobs that do not count while travelling;
  - body-pulls at levels 1-2;
  - interacts only with objects that count;
  - turns in a quest when passing a "?";
  - switches to whichever mob is attacking;
  - breaks off from mobs it cannot reach.
- **The bottleneck is the state, not the facts.** Grok's states often read `level: "unreadable"`. They never say
  whether a mob counts for an objective, or whether the player is travelling or hunting. Jev cannot judge
  "worth it?" without that information. The live hunt state already carries objectives, so 65% here is a lower
  bound on the description, not a score for live play.

## Techniques that already reached the code

These came from the owner's own recorded demo, which carries more trust than a stream. They are in M4b
(`../m4/Hunt.swift`, and 13 situations in `../m4/tabletop.py`):
- no mana gate before a pull;
- eat and drink below 80% health or 50% mana;
- the costs of melee and Lightning Bolt stated as facts;
- the cast pushback fact;
- the chase fact (a melee mob runs as fast as the character);
- skipping grey (tapped) plates;
- distance bands read from the red range digits on the hotkeys.

## Not committed

These files are third-party, large, or both. Anyone can regenerate them from the video IDs above:
- the videos;
- the frames and sheets;
- the full subtitle transcripts.

Raw capture of the owner's game stays untracked under `runs/`.

## Reproduce

```sh
python3 experiments/002_wow_visual/learning/video_jev.py --check        # offline; used by the gate
(set -a; . ./.env; set +a; KB=1 python3 experiments/002_wow_visual/learning/video_jev.py \
    experiments/002_wow_visual/learning/zerocks1/part1_decisions.jsonl)   # live Jev, provider call
```

## Next

1. Re-label the decision points from full-resolution crops of the tracker and the target frame, adding
   `counts_for_objective`, `activity` and `level`, and drop UI-only moments.
2. Add facts only for the recurring themes, and test them on a held-out part.
3. Repeat for episodes #2 and #3 (levels 5-10).
