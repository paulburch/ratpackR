# Bug-fix experiments: running log

Branch `bugfix-experiments`, cut from `bug-review`, so it has the Linux set-up and the checks.
Each fix is **one commit** that touches only the lines needed, so any fix can be reverted or
cherry-picked on its own. Bug numbers refer to `docs/bug_review.md`.

**Why this branch exists.** It answers one question: does fixing a bug on its own break other
parts of the code? Fixes are applied **cumulatively**, in severity order. Nothing here is
meant for upstream until Paul and André have reviewed it.

## How each fix is tested

```bash
bash docs/bugfix/run_fix_tests.sh <tag> ["1 2" or "1 2 99"]
```

For each fix, the script does three things:

1. Runs `docs/bug_checks.R`. The check for the fixed bug should change from CONFIRMED to
   NOT REPRODUCED. No other check should change.
2. Runs the smoke tests: Silver.warehou (`Inputs Buffer/`), 1 simulation and 1 projection
   year, at `Estimation.test` 1 (no estimation) and 2 (estimation with deterministic data).
   For fix #3 it also runs `Estimation.test` 99. Each run must finish without an error.
3. Compares every `Results/*.Out` file with the *previous* step, token by token, with a
   relative tolerance of 1e-8 (`docs/bugfix/compare_runs.R`). It reports which outputs change
   and by how much, so each change can be explained by the fix.

The results of each step are kept under `Temp/fixruns/<tag>/`. That folder is git-ignored and
can be rebuilt by re-running the script. The summary of each step is copied into this log.

**Limits of the tests.**
- Bugs #4–#8 and several others only affect multi-stock or multi-area runs. The repository
  has no complete multi-stock or multi-area input set, so for those the evidence is the
  synthetic check in `bug_checks.R`. The smoke test only shows that the single-stock path is
  unchanged.
- Some checks in `bug_checks.R` reproduce the faulty construct in isolation (B06, B07, B08,
  B11, B13). They keep reporting CONFIRMED after a fix; this is noted under each fix.

## Status

| Step | Bug | Fix | Checks | Smoke E1/E2 | Outputs changed | Verdict |
|---|---|---|---|---|---|---|
| 0 | – | baseline (unfixed) | 20 CONFIRMED | pass / pass (E99 pass) | – (repeat run identical) | – |

## Notes per step

### Step 0: baseline
- Smoke tests on the unfixed code: E1 94 s, E2 95 s, E99 99 s; all exit 0.
- All 20 checks CONFIRMED; B19 is INFO only.
- **Repeatability:** re-running E1 on unchanged code gave identical output in all 11 files,
  so every difference in later steps is caused by the fix.
