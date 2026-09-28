---
title: "A merge is done when its readback says MERGED: exact verdict lines, no piped merge, cleanup after"
date: 2026-09-28
category: workflow-issues
module: AI-SDLC merge (tools/sdlc merge)
problem_type: workflow_issue
component: development_workflow
severity: medium
root_cause: missing_workflow_step
resolution_type: workflow_improvement
applies_when:
  - "An independent reviewer's verdict is about to be posted for tools/sdlc merge"
  - "tools/sdlc merge --execute is about to run inside a longer shell command"
  - "A PR's branch or worktree is about to be deleted after a merge"
symptoms:
  - "PR #53 held on 'no trusted exact-head review verdict' while its verdict was an issue comment"
  - "PR #99's verdict lines ended in two spaces, so the merge held, yet a piped command chain deleted the branch and closed the PR"
tags: [ai-sdlc, merge, review-verdict, exit-status, cleanup, github]
---

# A merge is done when its readback says MERGED: exact verdict lines, no piped merge, cleanup after

## Context

`tools/sdlc merge PR FULL_HEAD_SHA` merges only on a trusted verdict for the exact head. The tool did what it was designed to do on both occasions below. The mistakes were in how its input was posted and how its result was read.

- **Where it reads.** Only PR reviews count, and only on the head commit, from an owner, member or collaborator (`tools/Merge.swift:161-163`). REVIEW.md already says "Submit a GitHub **COMMENT** review on the exact commit" (`REVIEW.md:37`).
- **How it reads.** Whole lines. `verdictLines` splits the body at "\n" only (`tools/Merge.swift:110-111`). A line must equal "AI-SDLC review: PASS" (`:166`), an Independence line must match one of three values exactly (`:179`), and a "Head: <sha>" line must match exactly (`:181`). So "AI-SDLC review: PASS" followed by two spaces is not a verdict.
- **How it fails.** Any hold writes `HOLD: …` to stderr and returns 1 (`tools/Merge.swift:249-255`). `tools/sdlc` `exec`s the binary (`tools/sdlc:20`), so that status is the command's own.
- **How it succeeds.** With `--execute`, it reports `"decision": "MERGED"` and a `merge_sha` only after GitHub's readback of the PR agrees (`tools/Merge.swift:238-245`).

**PR #53 (27 September), GitHub's timeline:**
- 02:51:24 UTC: the verdict was posted with `gh pr comment`, as an issue comment. The merge held on "no trusted exact-head review verdict".
- 02:58:21: the same text was posted as a COMMENTED review.
- 02:58:35: the PR merged.

**PR #99 (28 September), GitHub's timeline:**
- 00:54:54: the independent reviewer's output was posted as a review. Its first two verdict lines ended in two spaces, a Markdown line break: "AI-SDLC review: PASS  " and "Independence: fresh-context  ".
- The operator ran `sh tools/sdlc merge 99 <sha> --execute | tail` inside an `&&` chain that went on to delete the branch. The merge printed `HOLD: no trusted exact-head review verdict`. A pipeline's status is its last command's, though, and `tail` exits 0, so the chain continued:
  - 00:55:05: the PR was closed, as deleting its remote branch closes it;
  - 00:55:06: the head branch was deleted.
- Recovery:
  - 00:55:12: the head SHA was pushed back to the branch;
  - 00:55:15: `gh pr reopen`;
  - 00:55:23: the same review was posted again with clean lines.
- 01:02:13: the PR merged.

The sequence of commands comes from the agent's private memory notes (auto memory [claude]). The review bodies and all the times above are on GitHub: for #99 in `gh api repos/<owner>/<repo>/issues/99/events` and `…/pulls/99/reviews`, and for #53 in `…/issues/53/comments`, `…/pulls/53/reviews` and `…/issues/53/events`.

## Guidance

Treat the merge tool's exit status and readback as the only signal. Printed text and a pipeline's status are not.

1. **Post the verdict as a review, with clean lines.** Reviewer output often ends lines with two spaces. Strip trailing whitespace, then check that the three lines are there exactly before posting:

   ```sh
   sed -E 's/[[:space:]]+$//' review.txt > review.clean.txt
   grep -cxF "AI-SDLC review: PASS" review.clean.txt                                        # expect 1
   grep -cxE "Independence: (fresh-context|author-review|deterministic)" review.clean.txt   # expect 1, and the true one
   grep -cxF "Head: $SHA" review.clean.txt                                                   # expect 1
   gh pr review "$PR" --comment --body-file review.clean.txt
   ```

   Count each line on its own: one pattern with alternatives would also count three PASS lines as three. The Independence line states how the review was made; it is never changed to pass the check.

2. **Run the read-only check first, then `--execute` on its own, with nothing piped after it.** Send the output to a file if it needs reading later. If a pipe is unavoidable, use `set -o pipefail`.

   ```sh
   sh tools/sdlc merge "$PR" "$SHA"                                     # expect "decision": "ELIGIBLE"
   sh tools/sdlc merge "$PR" "$SHA" --execute > merge.txt 2>&1; echo "exit $?"
   ```

3. **Clean up only after MERGED is confirmed twice.** First, `merge.txt` must show `"decision": "MERGED"` and a `merge_sha`. Second, `gh pr view "$PR" --json state,mergeCommit` must say `MERGED` with the same commit. Only then remove the worktree and delete the local and remote branch.

4. **A fix makes a new head, so post a new verdict.** "A changed head invalidates the verdict" (`REVIEW.md:52`). Re-run the review on the new head and post it again before merging.

The strictness belongs to the tool's design: whole-line matching, as its comment at `tools/Merge.swift:110` describes. Loosening it would change governance. The operator's steps above are the fix, not a change to the tool.

## When to Apply

Every time reviewer output becomes a PR review, and every merge.

The same rule holds for any destructive step that follows a check, such as deleting a branch, removing a worktree or closing a PR. Gate it on the tool's exit status and on GitHub's readback, never on text that was printed or on a pipeline's status.
