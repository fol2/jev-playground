# Closing four review findings — 21 September 2026

Findings raised in the exact-head review of PR #7 and fixed on the experiment branch
after it merged. None of them blocked that merge; each is a gap in what the evidence
proves rather than a defect in the delivered behaviour.

## 1. The matcher corpus did not protect either decision constant

`MotionChecks.swift` compared the current matcher against a frozen copy of the previous
one over 160 cases. The generator only produced near-ideal translations, correlation
close to 1, or cases rejected on structure, so nothing scored near a threshold.
Changing the `0.55` accept threshold to `0.50`, or the `0.10` ambiguity margin to
`0.02`, in `motion.swift` alone left all 174 checks green with an identical
32 accepted / 128 abstained split.

The suite now adds 24 cases that those constants actually decide: twelve blend the
signal toward noise to sweep correlation down through the accept threshold, and twelve
stamp two non-overlapping in-radius copies of the anchor to produce a confident match
with a real rival, sweeping the ambiguity margin through its threshold. The frozen
reference takes both constants as parameters, defaulting to the frozen values, so the
suite asserts directly that at least one case is decided by each. That coverage
assertion is the durable part: the sweep cannot drift out of the band unnoticed.

Verified by mutation: `0.55` to `0.53`, `0.55` to `0.50`, `0.10` to `0.08` and `0.10`
to `0.02` are each now caught, as is the previously caught boundary-peak guard.

## 2. A gutted test file still produced a green visual check

Deleting `test_observations.py` correctly failed the gate, but removing only its
`unittest.main()` line left `python3 test_observations.py` exiting 0 having run nothing.
The gate now loads the module, counts the suite and runs it itself, so the check no
longer depends on the file's own entry point. A module that imports but carries no
tests, an empty case and a missing module all fail, and each is covered by a test that
executes the real command string rather than asserting its shape.

## 3. The merge helper could not gate a non-main target

`tools/merge_pr.py` required `base == "main"`, so a PR targeting an experiment branch
returned `HOLD: unexpected integration branches` and the predicates had to be applied by
hand. The helper now takes `--into`, defaulting to `main`, and records the integration
branch in its decision. A named target still has to include current main, which is now a
separate compare rather than a side effect of the base check. The branch name is
interpolated into an API path, so traversal, empty and absolute segments are rejected.

## 4. The gate manifest could not be reproduced

`manifest_sha256` hashed the report including `elapsed_seconds`, so two runs over
identical content always disagreed and the value anchored nothing. The published
`b549a9fa...` for PR #7 could not reproduce; the run tree `613fe3f0...` did, exactly.
The hash is now taken before timing is added, and tests assert that wall clock does not
change it, that every decided field still does, and that a reader can recompute it from
the published report.

## Non-goals

- No fishing runtime behaviour, threshold, recovery branch or input path is changed.
- No live validation, capture, provider call or Mac-local effect.
- The visual boundary remains a provenance and shape check with no recogniser behind it.
