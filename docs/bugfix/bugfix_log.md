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
| 3 | #3 clean-up never runs | `!Estimation.test %in% 99` → `Estimation.test %in% 99` | none changed | pass / pass (E99 pass) | E1/E2 identical; E99 folder 11 MB → 1.7 MB | safe |
| 4 | #4 Istocks loop | loop variable Istock | B09 fixed; others unchanged | pass / pass | identical (single stock) | safe; multi-stock untested end-to-end |
| 5 | #5 PGMSY 0/0 | zero-catch linked fleet treated as unlinked | B14 fixed; others unchanged | pass / pass | identical (PGMSY off) | safe; rule to confirm |
| 6 | #6 TAC.mat byrow | no byrow, only own areas | none changed (B08 is a stand-alone replica; new expression verified separately) | pass / pass | identical (NassArea 1) | safe |
| 7 | #7 SPR_ref multi-area | destination area, transposed plus group, catch over all areas | B10a, B10c fixed; others unchanged | pass / pass | identical (1 area) | safe |
| 8 | #8 movement age a-1 vs a | equilibrium code uses Move[,,Iage] like the projection (to confirm) | B10b fixed; others unchanged | pass / pass | identical (1 area) | safe; convention to confirm |
| 9 | #9 steepness bias | h_init = h × bias (negative = fixed) | B05 fixed; others unchanged | pass / pass | identical (Silver uses fixed h) | safe; watch h bounds >1 |
| 10 | #10 Early-R0 block-end name | single name .end.yrs with default | B04 fixed; others unchanged | pass / pass | identical | safe |
| 11 | #11 catch-bias rows | per-fleet row; fill to last model year | B03a, B03b fixed; others unchanged | pass / pass | identical (all biases 1) | safe |
| 12 | #12 Tier 4b CPUE limit | compare with Cpue.limit | none changed (B06 is a stand-alone demo; rule verified separately) | pass (E1 only) | identical (Tier 4b unused) | safe; not run end-to-end |

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

### Step 3: bug #3, SS folder clean-up never runs (`Assessment.R:1844`)
- **Change:** `if (!Estimation.test %in% c(99) & ...)` becomes `if (Estimation.test %in% c(99) & ...)`.
- **Checks:** none changed. No check exercises the clean-up.
- **Smoke tests:** E1 87 s, E2 92 s, E99 95 s; all exit 0. E1 and E2 outputs are identical,
  as expected, because they return before the clean-up.
- **E99:** the EM folder shrank from **11 MB to 1.7 MB**. It keeps `Report.sso`, `data.dat`,
  `data.ctl`, `starter.ss`, `forecast.ss`, `ss3a.par` and `ss3.log`; the `ss3` binary, `.sso`
  dumps and `ss3.par/.rep` are deleted. TACs are computed before the clean-up, so results are
  unaffected. Each assessment writes a new folder and `.par` file, so later assessments do
  not need the deleted files. `Check.Setup.R` reads `Report.sso`, which is kept.
- **Remaining warnings:** `cannot remove file 'FALSE'`, from bug #23 (`showWarnings=F`), and
  `cannot remove file 'ss.log'` (SS writes `ss3.log` on Linux).
- **Verdict:** safe; nothing else breaks.

### Step 4: bug #4, allocation loop `Istocks` (`RatpackR.R:1314`)
- **Change:** `for(Istocks in 1:Nstocks)` becomes `for(Istock in 1:Nstocks)`.
- **Checks:** B09 changed to NOT REPRODUCED. No other check changed.
- **Smoke tests:** E1 84 s and E2 92 s, both exit 0. All outputs are identical, as expected
  for a single stock (`Istock` was already 1).
- **Limit:** the multi-stock effect (each stock re-allocated, not only the last) could not be
  run end to end, because there are no complete multi-stock inputs.
- **Verdict:** safe for single-stock runs; the multi-stock behaviour is untested beyond the
  code check.

### Step 5: bug #5, PGMSY divides by zero (`RatpackR.R:78-79`)
- **Change:** a fleet linked to a primary stock with zero recent catch on that fleet
  (`Catch.Comp == 0`) is treated like an unlinked fleet: its TAC for the bycatch stock is
  carried over.
- **Checks:** B14 changed to NOT REPRODUCED.
  - With the zero-catch fleet's TAC at 0, there is no longer a crash.
  - With that TAC at 1 t, the primary TAC becomes (66.7, 0.67) instead of (0, 0). That is
    ordinary PGMSY scaling: the bycatch stock's predicted catch is 10 t on fleet 1 plus
    5 t carried over on fleet 2, against its 10 t TAC, giving a factor of 2/3.
  - No other check changed.
- **Smoke tests:** E1 89 s and E2 92 s, both exit 0. Outputs are identical (single stock,
  PGMSY off).
- **Verdict:** safe. Carrying over the TAC is a design choice; André may prefer another rule.

### Step 6: bug #6, `TAC.mat` reshape (`RatpackR.R:1344, 1365`)
- **Change:** `matrix(TACs[Istock,1:NassArea,,1], nrow=NassArea, ncol=Ncat_fleet)`, without
  `byrow=T` and limited to the stock's own assessment areas.
- **Checks:** none changed. B08 reproduces the old expression in isolation, so it still says
  CONFIRMED. The new expression was checked separately: two areas with fleet TACs (10,20,30)
  and (1,2,3) give (11, 22, 33), and a stock with fewer areas than `MaxAssArea` gives
  (10, 20, 30).
- **Smoke tests:** E1 89 s and E2 93 s, both exit 0. Outputs are identical (`NassArea = 1`).
- **Verdict:** safe.

### Step 7: bug #7, `SPR_ref` movement and catch (`RatpackR.R:836-863`)
- **Change:** three edits:
  - (a) numbers are added to the destination area, `Neqn[Jarea,...]`;
  - (b) the plus-group movement matrix is transposed, as in `Get.Initial`;
  - (c) the catch is summed over all areas (`for (Iarea in 1:Narea)`).
- **Checks:** B10a and B10c changed to NOT REPRODUCED.
  - Area 2 now holds 2.985 fish per recruit (it was 0).
  - Catch with two identical areas is 0.364, exactly 2 × the one-area value of 0.182.
  - B10b, the movement-age mismatch (bug #8), still fails, as expected. It is also why
    `SPR_ref`'s 2.985 differs from the projection rule's 2.844.
- **Smoke tests:** E1 90 s and E2 94 s, both exit 0. Outputs are identical (`Narea = 1`,
  `Move = 1`).
- **Verdict:** safe for single-area runs; correct for multi-area runs in the synthetic test.

### Step 8: bug #8, movement age index (`RatpackR.R:837, 1006, 1115`)
- **Change:** `Get.Initial`, the equilibrium-catch loop and `SPR_ref` now use
  `Move[Iarea,Jarea,Iage]`, the age fish have just reached, as `Project.One.Ahead` does.
  **This is a modelling choice André should confirm.** The alternative is to change
  `Project.One.Ahead` to `Iage-1`.
- **Checks:** B10b changed to NOT REPRODUCED. `Get.Initial`, `SPR_ref` and the projection rule
  now agree exactly (2.844 fish per recruit in area 2; maximum difference 0.000).
- **Smoke tests:** E1 89 s and E2 93 s, both exit 0. Outputs are identical (single area).
- **Verdict:** safe for single-area runs; consistent across the three routines for multi-area
  runs.

### Step 9: bug #9, steepness bias ignored (`Assessment.R:698`)
- **Change:** `Initial.val <- Ass$SR_Steep*Ass$SS_Steep_Bias`. Negative values still mean
  "fix h at |value|", as for M.
- **Checks:** B05 changed to NOT REPRODUCED. With bias 0.8 and true h 0.75, the EM now starts
  at h = 0.600. No other check changed.
- **Smoke tests:** E1 90 s and E2 93 s, both exit 0. Outputs are identical: Silver.warehou
  uses bias −0.6 (fixed h), which was already handled.
- **Side effect to watch:** `Do_Jitter` sets the bounds to value/`Bound_mult` and
  value × `Bound_mult`. A bias above 1, or a large `Bound_mult`, can give an upper bound
  above 1 for h, which SS may reject. This was already possible before the fix.
- **Verdict:** safe.

### Step 10: bug #10, early-R0 block end name (`ReadIn.R:1004`, `RatpackR.R:1146,1148`)
- **Change:** one name, `Early.R0.mult.end.yrs`, with default `c(0,0)`. This also stops a
  latent NULL error at `ReadIn.R:1020` when `#Early_R0Mult` is given without
  `#Early_R0Mult_Block_end`.
- **Checks:** B04 changed to NOT REPRODUCED. No other check changed.
- **Smoke tests:** E1 93 s and E2 94 s, both exit 0. Outputs are identical: Silver.warehou has
  no early-R0 multiplier.
- **Note:** Morwong and P.cod use `#Early_R0Mult`, but their block starts at 0 and they have
  no equilibrium catch, so they follow the same code path as before.
- **Verdict:** safe.

### Step 11: bug #11, catch-bias rows (`ReadIn.R:1655-1679`)
- **Change:** each fleet reads its own row, `AllInput[Index2,...]` (9 references in the
  block). The last segment now fills to the end: `YrN` is compared with `Nhist+Nproj+1`.
- **Checks:** B03a and B03b changed to NOT REPRODUCED. Fleet 2 now gets its own 0.5, and
  2010 gets 1.2. No other check changed.
- **Input check:** every `.OM` file in the repo has exactly one bias row per fleet
  (catch and survey fleets; 18 files), so the per-fleet read is valid everywhere. All values
  are currently 1.
- **Smoke tests:** E1 89 s and E2 92 s, both exit 0. Outputs are identical.
- **Verdict:** safe.

### Step 12: bug #12, Tier 4b CPUE limit (`Assessment.R:2231`)
- **Change:** `if (CpueAvg <= Cpue.limit)`. The old test used `Tier4b$Cpue_lim`, which
  partially matched the multiplier `Cpue_limit_mult`.
- **Checks:** none changed. B06 demonstrates R's partial matching in isolation, so it still
  says CONFIRMED. The corrected rule was checked separately (target 1, limit 0.4): CPUE 0.2
  and 0.4 give multiplier 0; 0.7 gives 0.5; 1.0 gives 1; 1.3 gives 1.5. The RBC can no
  longer go negative. Above the target the multiplier exceeds 1, and only `Max.catch` caps
  it; that is André's design and unchanged.
- **Smoke test:** E1 only, 90 s, exit 0. Outputs are identical; Tier 4b is not used by any
  current input.
- **Verdict:** safe, but not exercised end to end.
