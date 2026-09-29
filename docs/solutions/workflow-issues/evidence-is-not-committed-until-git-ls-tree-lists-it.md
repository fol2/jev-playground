---
title: "Evidence is not committed until git ls-tree lists it; never name a repo evidence folder runs/, data/ or .evidence/"
date: 2026-09-28
category: workflow-issues
module: evidence commits (.gitignore, git ls-tree, check-ignore)
problem_type: workflow_issue
component: development_workflow
severity: high
root_cause: missing_workflow_step
resolution_type: workflow_improvement
applies_when:
  - "Evidence, replay results or a count of committed files is about to be reported as committed, pushed or available to a reviewer"
  - "A new folder for evidence, fixtures or outputs is about to be named anywhere in the repo"
  - "A folder or file at any depth would be named runs, data or .evidence"
  - "A local check passes on a new evidence path that a fresh checkout has never seen"
symptoms:
  - "On 24 Sept the agent told the owner the video-replay mismatch files were pushed; they were not in the commit"
  - "A reviewer found the nested runs/ folder missing from the tree, so 153/236 and three other figures stayed unrecomputable reported results"
  - "git add of the parent folder skipped the ignored runs/ with no message and exit 0"
related_components:
  - learning-evidence
  - gitignore
  - review
tags: [gitignore, git-ls-tree, check-ignore, evidence, provenance, runs-directory, silent-exclusion]
---

# Evidence is not committed until git ls-tree lists it; never name a repo evidence folder runs/, data/ or .evidence/

## Context

`.gitignore` has three bare directory patterns: `data/` (`.gitignore:5`), `runs/` (`:6`) and `.evidence/` (`:7`). In git, a pattern whose only slash is a trailing one matches a directory of that name at any depth. Only a leading or middle slash ties it to the folder the `.gitignore` sits in. On main today:

```text
$ git check-ignore -v experiments/x/runs/a experiments/x/data/a experiments/x/.evidence/a runs/a
.gitignore:6:runs/	experiments/x/runs/a
.gitignore:5:data/	experiments/x/data/a
.gitignore:7:.evidence/	experiments/x/.evidence/a
.gitignore:6:runs/	runs/a
$ git check-ignore -v experiments/x/replay_mismatches/a      # no output, exit 1: not ignored
```

The root `runs/` is ignored on purpose. It is the private evidence folder. The Swift tools write frames and memory there (for example `experiments/002_wow_visual/m4/QuestProbe.swift:42-48`, `experiments/002_wow_visual/m5/PerceiveTool.swift:26`), and `AGENTS.md:61` says "Never commit or print secrets, private captures or credential dumps". Evidence meant to be public needs "a deliberately tracked path: an ignored `runs/` directory is not a published result" (`experiments/README.md:32-34`).

**The incident, PR #18 (merged 24 September).**

- The PR's learning commit reported that Jev agreed with the human on 153 of 236 video-replay decisions. Its message listed "live-Jev replay mismatches" (PR #18's squashed commit message). Its README said the mismatches were in the video's folder under `runs/` (`<video>/runs/`; here `<video>` stands for that video's folder, which `experiments/002_wow_visual/learning/README.md:36-45` names). That folder was not in the commit: `.gitignore:6` had dropped it, and nothing warned. The same README also said raw capture "stays untracked under `runs/`", so the rule was known. Its reach into a nested folder was not.
- The agent told the owner the mismatch files were pushed before it listed the commit (auto memory [claude]).
- A peer review of that head returned REQUEST_CHANGES. Its finding: the learning tree had no such folder, "Therefore 153/236, the +2 KB difference, the 4/5 selected-probe change and the 30-40% mismatch estimate remain reported results." (`experiments/002_wow_visual/learning/review_20260924.md:70-76`).
- A later commit in the same PR added the six files unchanged under `replay_mismatches/` in the same video folder (`experiments/002_wow_visual/learning/README.md:36-45`). `--check` now reads each file and holds unless its rows reproduce the table (`experiments/002_wow_visual/learning/VideoJev.swift:189-205`). The motor proof runs it (`tools/MotorProof.swift:567`). The PR's final review recorded: "The historical replay mismatches were hidden by the `runs/` ignore rule: resolved."

**What checks tracking today: nothing general.**

- `tools/Gate.swift:203` walks `git ls-tree` of the head, but only to check file modes and to route every tracked file through the selector. It never compares the tree with the paths a PR or doc cites.
- `REVIEW.md:21-23` asks whether a claim can be traced to a real source. It does not ask whether the cited files are in the tree.
- The compound-engineering plugin's claims validator (external tooling, not in this repo) checks cited paths, but only in `docs/solutions/` docs, and only when that workflow runs.
- The gate's clean-tree check runs `git status --porcelain --untracked-files=all` (`tools/Gate.swift:193`). That does not list ignored files. So an ignored file on the author's disk does not make the tree dirty, and a local check can still read it. Only a fresh checkout sees the file missing: hosted CI, a new clone or a worktree.

## Guidance

**Before you say evidence is committed, list it in the commit. Before you name an evidence folder, ask the ignore rules.**

1. **Ask git about the name first.** Run `git check-ignore -v <dir>/<folder>/<file>`.
   - Output such as `.gitignore:6:runs/	<path>` means the path is ignored, and names the line and the pattern.
   - No output (exit 1) means not ignored, *or* already tracked, because check-ignore skips tracked files unless you add `--no-index`. The 39 force-added files under `data/001_wow_fishing/` are tracked, but a new file beside them is still ignored (`.gitignore:5:data/`).
2. **Never call a repo evidence folder `runs/`, `data/` or `.evidence/`, at any depth.** Use a name that says what it holds, such as `replay_mismatches/`.
3. **Before you commit, look for what `git add` will skip.** Run `git status --short --ignored -- <dir>`.
   - `!!` is an ignored path that exists on disk. `??` is untracked. `A` and `M` are staged.
   - `git add <parent>`, `git add .` and `git add -A` skip ignored paths without a message and exit 0. Only naming the ignored path itself prints "The following paths are ignored by one of your .gitignore files". This was checked in a scratch repo on 28 September.
4. **After you commit, and before you write "committed" or "pushed", list the commit.** Every file the PR or doc cites must be in the list.

   ```sh
   git ls-tree -r --name-only HEAD -- <dir>
   git fetch && git ls-tree -r --name-only origin/<branch> -- <dir>   # after a push
   ```

5. **Give tracked evidence a consumer that fails when a file is missing**, as `--check` now does for the mismatch files. A green local run does not prove the files are committed.
6. **When evidence is private and stays local, say so in the PR.**
   - Name the folder pattern and why it stays local (private captures).
   - Say it is not in the PR, and label its numbers as reported, not something a reviewer can recompute.
   - Publishing it later takes three things: a privacy review, a deliberately tracked path and a registered proof (`experiments/002_wow_visual/learning/README.md:113-115`).
   - Never list the private folder's contents.

**A proposal, not done: anchor the patterns as `/runs/`, `/data/` and `/.evidence/`.** Then only the root folders would be ignored, and a nested evidence folder with one of those names would no longer vanish. The trade-off: `QuestProbe.swift` and `PerceiveTool.swift` open `runs/002_wow_visual/…` relative to the current directory. Run from a subfolder, they would create a nested `runs/` full of private frames. Today that folder is ignored. After anchoring, `git add -A` would pick it up. The naming rule costs nothing and keeps that protection.

## Why This Matters

- An ignored folder never reaches a reviewer, a clone, a worktree or hosted CI (a worktree has no `runs/`: `docs/solutions/workflow-issues/live-run-harness-and-envelope-belong-in-the-repo.md:114`). A number whose evidence is not in the tree is a report, not a result. In PR #18 this cost a REQUEST_CHANGES round and turned four figures into "reported results".
- Telling the owner "pushed" without checking costs trust (auto memory [claude]). "Unrelated green checks and unobserved success are not evidence" (`AGENTS.md:18`).
- The loss is silent in every everyday command. `git status` and `git add .` say nothing.
- The rule protects private captures. Do not weaken it to make up for a naming mistake.

## When to Apply

- Creating a folder for evidence, fixtures or outputs anywhere in the repo.
- Before writing "committed", "pushed" or "in the PR" about a file: in a PR, a doc, a review or a message to the owner.
- Reviewing a PR that cites evidence files: list the head's tree for them.
- A local check passes on a new evidence path: the file may exist only on your disk.

## Examples

**Before (PR #18's reviewed head).** The README pointed at `<video>/runs/`. `git ls-tree -r --name-only <head> -- experiments/002_wow_visual/learning/<video>` listed `brief.md`, three `part*_decisions.jsonl`, three `part*_techniques.md` and `regen_probe.jsonl`, but no mismatches.

**After (main today).**

```text
$ git ls-tree -r --name-only HEAD -- experiments/002_wow_visual/learning/<video>/replay_mismatches
…/replay_mismatches/part1_facts.mismatches.jsonl
…/replay_mismatches/part1_kb.mismatches.jsonl
…   (six files: part1-3, facts and kb)
$ git check-ignore -v experiments/002_wow_visual/learning/<video>/replay_mismatches/part1_kb.mismatches.jsonl
                                                   # no output, exit 1
```

**The silent skip, in a scratch repo:**

```text
$ printf 'runs/\n' > .gitignore
$ git add learning                                 # exit 0, no message
$ git status --short --ignored
A  learning/video1/b.jsonl
!! learning/video1/runs/
$ git add learning/video1/runs                     # exit 1
The following paths are ignored by one of your .gitignore files:
learning/video1/runs
```

**A PR line for private evidence:**

> Evidence: <n> live frames, kept local under the ignored `runs/002_wow_visual/<run>/` (private captures, `AGENTS.md:61`). They are not in this PR, so the counts above are reported and cannot be recomputed from the tree.

## Related

- [A merge is done when its readback says MERGED](../workflow-issues/merge-is-done-when-the-readback-says-merged.md): the same family. Read the artefact back before you claim done: there GitHub's MERGED readback, here the commit's tree.
- [Keep the live-run harness and envelope in the repo](../workflow-issues/live-run-harness-and-envelope-belong-in-the-repo.md): recordings stay under the ignored `runs/` (`:97`), and a worktree has no `runs/` (`:114`).
- [Count and calibrate pixels with the runtime's Swift reader](../workflow-issues/count-pixels-with-the-swift-reader-not-pil.md) (#119): name the source of every number. Here, that means saying whether the evidence is in the tree or only on your disk.
- `experiments/README.md:32-36`; `experiments/002_wow_visual/learning/README.md:36-45` and `:113-115`; `experiments/002_wow_visual/learning/review_20260924.md:70-76`.
- PR #18.
