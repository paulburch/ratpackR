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
| 1 | #1 FixedCosts NA | default 0 if 5th value absent | B02, B02b fixed; others unchanged | pass / pass | Cost/Profit columns NA → numbers only | safe |
| 2 | #2 SetBuffer | Buffer = max(Min, Buffer×TimeBuffer) (intent to confirm) | B01 fixed; others unchanged | pass / pass | 2026 TAC ×0.9 (6727→6054 t E1); 2027 state follows | works; changes buffer-study TACs |

## Notes per step

### Step 0: baseline
- Smoke tests on the unfixed code: E1 94 s, E2 95 s, E99 99 s; all exit 0.
- All 20 checks CONFIRMED; B19 is INFO only.
- **Repeatability:** re-running E1 on unchanged code gave identical output in all 11 files,
  so every difference in later steps is caused by the fix.

### Step 1: bug #1, `FixedCosts` (`ReadIn.R:1730`)
- **Change:** read the 5th economic value with `suppressWarnings`, and keep the default 0 when it
  is absent or non-numeric. The current 4-column inputs and future 5-column inputs both work.
- **Checks:** B02 and B02b changed to NOT REPRODUCED. No other check changed.
- **Smoke tests:** E1 87 s and E2 92 s, both exit 0.
- **Outputs:** only cost and profit columns changed, and only from `NA` to numbers. These are
  `ProjectAll` columns 13–14, 10 columns in `ProjectFleet` and `ProjectFleetArea`, and 65 in
  `ProjectIns`. No other value changed anywhere. In the first historical year of E2, Cost is
  7.6e-6 and Profit 0.059; these are placeholder economics, with all inputs set to 1.
- **Verdict:** safe; nothing else breaks.

### Step 2: bug #2, `SetBuffer` (`RatpackR.R:29`)
- **Change:** `Buffer <- max(Min.Buffer, Buffer*T.Buffer)`. This **assumes the default and
  time buffers multiply**; André should confirm. The alternative is `Buffer - Time*Stale.rate`.
- **Checks:** B01 changed to NOT REPRODUCED. No other check changed.
- **Smoke tests:** E1 88 s and E2 92 s, both exit 0.
- **Outputs:** only the projection rows changed (2026 and 2027). The 2026 post-buffer TAC is
  now exactly 0.9 × the retained TAC: E1 6726.6 → 6053.9 t, E2 2147.5 → 1932.8 t. The 2026
  catch and the 2027 stock state change as a result, by 10–12%. RBCs and the historical
  period are identical.
- **Verdict:** works as intended, with no side effects. **This changes TACs in the
  buffer-study inputs** (`Inputs Buffer/Silver.warehou.EM`, default 0.9). Any earlier buffer
  results with that file did not include the 0.9 default.
