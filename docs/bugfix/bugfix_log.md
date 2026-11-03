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
| 13 | #13 DataGen discard ages | Stock[[Istock]]...[Iarea,...] | none changed (B07 is a demo) | pass (E1 only) | identical; with discard ages on: old code crashes, new code runs | safe, verified end-to-end |
| 14 | #14 Tier 5 / no TAC management crash | TAC array set to 0 (F from F.fix) | none changed | pass / pass | identical; Tier 5 run: old crashes, new completes | safe, verified end-to-end |
| 15 | #15 CatchType 3 index | F.Selex.Inp[,Ifleet,] (zero F fill still open) | none changed (B12 is a demo) | pass (E1 only) | identical | crash fixed; CatchType 3 still needs data |
| 16 | #16 Tier 4a map logr | logR | none changed (B20 is a demo) | P.cod Tier 4a: old crashes, new completes | n/a | safe; Tier 4a gives RBC 0 for P.cod in both settings (investigate) |
| 17 | #17 Parallel drift | not attempted (needs a rebuild of the parallel files) | – | – | – | open |
| 18 | #18 CPUE double selectivity | drop SelexAge (already in SelRetWghtAge) | none changed | pass / pass | identical (0/1 selectivity in all inputs) | safe |
| 19 | #19 CatchDiscardl typo | CatchDiscard; $Full → $FullF | none changed | pass (E1) | ProjectFleetArea discards 0 → 6792 t (= ProjectAll) | safe |
| 20 | #20 rec-dev bias ramp | calendar years; 1 → 0 over the ramp | none changed (B13 is a demo) | pass / pass | identical | safe |
| 21 | #21 RNG streams restarted | set.seed(NextSeed) | B16 fixed; others unchanged | pass (E1, E99) | E1 identical; E99 draws change (RBC 59 369 → 29 659 t, 1 sim) | safe; breaks draw-for-draw reproducibility with old runs |
| 22 | #22 LengthData seed row | width 7+Nsex*Nlen | B18 fixed; others unchanged | pass (E1) | identical; rbind warning gone | safe |
| 23 | #23 file.remove showWarnings | argument dropped (calls already guarded) | none changed | pass (E1, E99) | identical; FALSE-file warnings 4 → 0 | safe |
| 24 | #24 WriteInsurance totals | rep(0,41) | none changed | pass (E1) | identical; 48 warnings gone | safe |
| 25 | S#25 + S#26 implementation-error block | per-stock TAC.management test; TACsStep[6] = implemented TAC | none changed | pass / pass | identical; with impl. error on, Target_catch NA → 3048.7 t | safe |
| 27 | S#27 area linear indexing (equilibrium block) | [Iarea,...] indexing | none changed | pass (E1); equilibrium-catch copy runs, old = new | identical (1 area) | safe; Assessment.R parts left (design) |
| 28 | S#28 Stock[[1]]$Nhist | Stock[[Istock]]$Nhist | none changed | pass (E1) | identical | safe |
| 29 | S#29 HybridA all areas closed (**now confirmed**) | skip normalisation when no open area (no catch) | none changed | pass (E1); closed-area copy: old crashes, new runs (catch 0) | identical | safe |
| 30 | S#30 MSY not 2/3 | explicit stop() with message | none changed | pass (E1); MSY 1 copy: clear error instead of "Fout not found" | identical | safe |
| 31 | S#31 SPR_ref year-1 biology | use M and fecundity of Iyear (design to confirm) | none changed | pass / pass | identical (TrueRBC 2504.2 t both) | safe; matters with time-varying M |
| 32 | S#32 `<-` on globals | `<<-` for General$Nsim and Stock$TheTACs | none changed | pass (E1); E0 before = after | identical | safe |
| 33–34 | S#33 TAC slot 50; S#34 one-sim return | no change (harmless / intended) | – | – | – | left as is |
| 35 | S#35 DataGen multi-area discards & CAA | sum over the assessment area's biological areas | none changed | pass / pass; CAA copy: old = new (127 rows) | identical (1 area) | safe; Write_data split left (design) |
| 36 | S#36 deterministic ages not normalised | Nsamp×Expected/sum | none changed | pass / pass | E1 identical; E2 parameters ≤1.9e-5 rel., TAC identical | safe |
| 37 | S#37 CAA seeds | use CAA.seeds | none changed | pass (E1); CAA copy runs, length bins resampled independently | identical | safe |
| 38 | S#38 env-index tautology | no change (intent unclear) | – | – | – | for André |

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

### Step 13: bug #13, discard-age expected values (`DataGen.R:111`)
- **Change:** `Stock[[Iarea,Istock]]$CatchAtAgeRet[Ifleet,,,Year]` becomes
  `Stock[[Istock]]$CatchAtAgeRet[Iarea,Ifleet,,,Year]`.
- **Checks:** none changed. B07 demonstrates the list-indexing error in isolation.
- **Smoke test:** E1 only, 91 s, exit 0. Outputs are identical; the standard inputs have no
  discard age data.
- **End-to-end test of the branch:** a copy of the Silver.warehou inputs
  (`Temp/DiscAgeInputs/`) with discard-age samples for fleet 1 in 2015–2019 (EFN 100):
  - **old code:** the run stops with `Error in Stock[[Iarea, Istock]] : incorrect number of
    subscripts`;
  - **fixed code:** the run completes (E1, 81 s), and the 5 discard-age samples
    (partition 1) are written to the SS `data.dat`.
- **Verdict:** safe; the fix is confirmed by running the branch end to end.

### Step 14: bug #14, no TAC management (Tier 5) uses undefined `TACsOrig` (`RatpackR.R:1258`)
- **Finding sharpened:** `TAC.management = "No"` is set only for **Tier 5** (`ReadIn.R:2257`),
  so the crash affects every Tier 5 run.
- **Change:** `TACsAdjust1[Istock,IassArea,,] <- 0`. With no TAC management there is no TAC;
  F comes from `Ass$F.fix`, which `Run_Tier5` sets. **Design choice:** 0, rather than NA or an
  RBC split, so later sums stay finite.
- **End-to-end test:** a copy of Silver.warehou with `#Ass_Basic:Type Tier_5`,
  `#Tier_5:Option 1` (mean F) and `#Tier_5:Years 2015 2020` (`Temp/Tier5Inputs/`):
  - **old code:** the run stops with `Error in Do.Project(Isim) : object 'TACsOrig' not found`;
  - **fixed code:** the run completes (E1, 73 s). The 2026 retained catch is 794 t, from the
    2015–2020 mean F. The TAC columns are NA, as expected without TAC management.
- **Checks:** none changed.
- **Smoke tests:** E1 91 s and E2 95 s, both exit 0. Outputs are identical; E2 was compared
  with step 11, the last E2 run.
- **Verdict:** safe. Tier 5 option 1 now runs.

### Step 15: bug #15, `ReviewFsolver` indexes the 3-D `F.Selex.Inp` with 2 subscripts (`RatpackR.R:1731`)
- **Change:** `sum(F.Selex.Inp[,Ifleet,])`. The fixed expression gives per-fleet totals on a
  1 × 4 × 46 test array (0, 4.6, 0, 0).
- **Not fixed:** for `CatchType` 3, `F.Selex.Inp` is still all zeros (`ReadIn.R:1085`; the fill
  from `OM.obj$Fleet.F.data` is commented out "AEP FIX"). That needs André's data source.
- **Checks:** none changed. B12 demonstrates the indexing error in isolation.
- **Smoke test:** E1 only, 90 s, exit 0. Outputs are identical; multispecies and
  `CatchType` 3 are not used.
- **Verdict:** safe, but only the crash is fixed; `CatchType` 3 is still unusable.

### Step 16: bug #16, Tier 4a `map` names `logr` (`Assessment.R:2126`)
- **Change:** `map <- list(logR=factor(NA))`.
- **Smoke script:** `RunStreams/RunSmokeTest.R` takes an optional 4th argument, the species,
  so other stocks can be tested.
- **End-to-end test:** P.cod (`Inputs Other/`), switched to `#Ass_Basic:Type Tier_4a` with
  `EstR No` and `EstZ Yes` (`Temp/Tier4aInputs/`):
  - **old code:** the run stops with `Names in map must correspond to parameter names`;
  - **fixed code:** the run completes (32 s).
- **Checks:** none changed. B20 calls `MakeADFun` directly with the bad name.
- **Observation (not caused by the fix):** both the fixed `EstR No/EstZ Yes` run and P.cod's
  own `EstR Yes/EstZ No` setting give **RBC = 0** in 2025, with `sdreport` warnings
  (`NaNs produced` in `sqrt(diag(cov))`). True 2025 depletion is 25%, between `alpha` (20%)
  and `beta` (35%), so with a good estimate the RBC should be positive. **The Tier 4a fit for
  P.cod should be checked**: it may underestimate depletion, or the Hessian may be singular.
  It is added to the review as a suspected issue.
- **Verdict:** safe; the crash is fixed. The Tier 4a performance for P.cod needs a separate
  look.

### Step 17: bug #17, `R Inserts/Parallel/` drift (not attempted)
- This needs the parallel copies **rebuilt** from the current `RatpackR.R`/`Assessment.R`,
  keeping only the `foreach` wrapper. That is a separate task, not a line fix, and it can't
  be tested meaningfully without a multi-core run design. It is left for a decision with
  André, since he may maintain the parallel version separately.

### Step 18: bug #18, catch-fleet CPUE predictions apply age selectivity twice (`RatpackR.R:553`)
- **Change:** `SelexAge[...]*` is removed in front of `SelRetWghtAge[...]`, which already
  includes it (`ReadIn.R:969`). The survey branch (line 555) was already correct.
- **Checks:** none changed. B19 is INFO only: 0 of 2304 values for Silver.warehou lie strictly
  between 0 and 1.
- **Smoke tests:** E1 91 s and E2 95 s, both exit 0. Outputs are identical, as predicted:
  with 0/1 age selectivity, squaring changes nothing. No current input has indexed catch
  fleets with 0 < age selectivity < 1, so the fix only matters for future inputs.
- **Verdict:** safe.

## Summary after the High and Medium fixes (steps 1–18)
- **Applied and tested:** 17 fixes (#1–#16 and #18), one commit each, cumulative.
  **No fix broke another part of the code.** Every smoke run completed. Each step changed only
  the check for the bug it fixed, and outputs changed only where the fix was meant to act:
  - #1: Cost and Profit columns go from NA to numbers;
  - #2: 2026 TAC ×0.9 in the buffer-study input;
  - #3: E99 folder 11 MB → 1.7 MB.
- **Fixes confirmed by running a branch that used to crash:** #13 (discard ages), #14
  (Tier 5) and #16 (Tier 4a `EstR No`/`EstZ Yes`).
- **Design choices André should confirm:**
  - #2: the buffer combination (multiplicative);
  - #5: the PGMSY rule for a zero-catch linked fleet;
  - #8: the movement age convention;
  - #14: a zero TAC without TAC management.
- **Still open:**
  - #15: `CatchType` 3 historical F is all zeros and needs a data source;
  - #17: the parallel rebuild;
  - the multi-stock and multi-area fixes (#4–#8) were checked only with synthetic cases;
  - new observation: Tier 4a gives RBC 0 for P.cod.
- **Not started:** the Low-severity items (#19–#24, plus the suspected list), pending Paul's
  go-ahead.

### Step 19: bug #19, `CatchDiscardl` typo (`WriteOut.R:304`, also `$Full` at 316)
- **Change:** `CatchDiscardl` becomes `CatchDiscard`. `$Full` becomes `$FullF`; it only worked
  through partial matching.
- **Checks:** none changed.
- **Smoke test:** E1, 98 s, exit 0. Only `ProjectFleetArea` changed: the per-area discard
  column now totals **6792 t** over the historical years (it was 0), matching the
  `ProjectAll` discards. No other file changed.
- **Verdict:** safe; an output-only fix.

### Step 20: bug #20, descending rec-dev bias ramp (`Assessment.R:1233`)
- **Change:** `Bias <- (Year+end_ramp+YrOffset - Iyear)/(end_ramp - last_fullbias)`. Calendar
  years are used throughout, and the ramp falls from 1 at the last full-bias year to 0 at the
  end of the ramp. The old numerator used the model year `Iyr` and was anchored at the wrong
  end. For a 6-year ramp the new values are 1, 0.833, 0.667, 0.5, 0.333, 0.167, 0.
- **Checks:** none changed. B13 evaluates the old formula on its own.
- **Smoke tests:** E1 97 s and E2 103 s, both exit 0. Outputs are identical to the previous
  steps; the only E2 difference from step 18 is the step-19 discard column. The branch only
  affects starting `.par` rec devs, and Silver.warehou never reaches it.
- **Verdict:** safe.

### Step 21: bug #21, random streams restarted (`ReadIn.R:1245`)
- **Change:** the discard deviations use `set.seed(NextSeed)` instead of `set.seed(Seed)`.
  The seed chain no longer restarts, so later streams no longer repeat earlier ones.
- **Checks:** B16 changed to NOT REPRODUCED. The age-sample seeds are no longer the uniforms
  that decide catastrophic M. No other check changed.
- **Smoke tests:** E1 97 s and E99 104 s, both exit 0. E1 is identical (deterministic data).
  In E99 (stochastic data) the 2026 RBC changed from 59 369 t (step 3) to 29 659 t, and the
  final TAC from 43 671 to 21 817 t. That is expected: the simulated discard, length, age
  and catch data now use different random numbers. With one simulation the RBC is very
  noisy, so the size of the change says nothing about bias.
- **Consequence:** stochastic runs after this fix will not reproduce earlier runs
  draw-for-draw, even with the same seeds. Distributions over many simulations should be
  equivalent.
- **Verdict:** safe; only the random draws change, by design.

### Step 22: bug #22, `LengthData` seed row width (`ReadIn.R:1335`)
- **Change:** `rep(0,7+Nsex*Nlen)`, the same width as the rows `DataGen` appends.
- **Checks:** B18 changed to NOT REPRODUCED. No other check changed.
- **Smoke test:** E1, 95 s, exit 0. Outputs are identical. The
  `number of columns of result is not a multiple` warning is gone (1 → 0).
- **Verdict:** safe.

### Step 23: bug #23, `file.remove(..., showWarnings=F)` (`Assessment.R`, 10 calls)
- **Change:** the `showWarnings=F` argument is dropped. `file.remove` has no such argument, so
  `FALSE` was treated as a file name. Every call is already guarded by `file.exists()`.
- **Checks:** none changed.
- **Smoke tests:** E1 94 s and E99 104 s, both exit 0. Outputs are identical: E1 against
  step 22, E99 against step 21. The `cannot remove file 'FALSE'` warnings in E99 went from 4
  to 0.
- **Verdict:** safe.

### Step 24: bug #24, `WriteInsurance` totals length (`WriteOut.R:463`)
- **Change:** `Totals <- rep(0,5+3+3*11)`, that is 41: 5 economic values, 3 expected profits
  and 3 values for each of the 11 insurance types. It was 35.
- **Checks:** none changed.
- **Smoke test:** E1, 94 s, exit 0. Outputs are identical; the sums were already correct
  through recycling. All 48 `longer object length` warnings per simulation are gone.
- **Verdict:** safe. **That completes the Low items (#19–#24).**

## Suspected items (#25–#45)

### Step 25: suspected #25 and #26, implementation-error block (`RatpackR.R:1306-1316`)
- **#25 change:** the `TAC.management=="Yes"` test moved inside `for (Istock ...)`. Before, it
  was evaluated once, with `Istock` left over from the previous loop (the last stock).
- **#26 change:** `TACsStep[6,Iyear] <<- sum(TACs[Istock,,,1])`, the implemented TAC. Before,
  it copied `Stock$TACs[Iyear]`, which is only set at line ~1396, so it held a stale value or
  NA.
- **End-to-end test:** a copy of Silver.warehou with `#Use.Implementation.Err 1` and
  `#Implementation.Err.Spec 1 20 20` (Beta(20,20) TAC multiplier, mean 0.5;
  `Temp/ImplErrInputs/`):
  - **old code:** the 2026 "Target_catch" column (`TACsStep` row 6) is **NA**, while the
    implemented TAC is 3048.7 t;
  - **fixed code:** row 6 is **3048.7 t**, equal to the implemented TAC and the retained
    catch. The other rows are unchanged.
- **Checks:** none changed.
- **Smoke tests:** E1 94 s and E2 98 s, both exit 0. Outputs are identical (implementation
  error off).
- **Verdict:** safe. #26 is a diagnostic-only fix; #25 matters only for multi-stock runs.

### Step 27: suspected #27, linear indexing of area matrices (`RatpackR.R:1150-1160`)
- **Change:** in the equilibrium-catch block, `EarlyDevs[1:MaxAge]` becomes
  `EarlyDevs[Iarea,1:MaxAge]`, `EarlyDevs[1]` becomes `EarlyDevs[Iarea,1]`, and `R0[1]`
  becomes `R0[Iarea,1]`; 2 occurrences each.
- **Not changed:** `Assessment.R:766,1250` (`Finitial[Ifleet]`) and `1238`
  (`Rec_devs[Iyr]`). The EM is single-area, so combining biological areas into the EM's
  starting values is a design decision for André.
- **End-to-end test:** no input has a non-zero equilibrium catch, so this block never runs
  today. I made a copy of Silver.warehou with equilibrium catch 100 t on fleets 1–2 and an
  initial F of 0.05 (`Temp/EqCatchInputs/`). The block ran in old and new code
  ("Doing initial catch" × 11), both completed, and the outputs are **identical** (single area:
  `[1,k]` and `[k]` are the same element). The initial stock starts at 64% depletion instead
  of 100%, so the block is active.
- **Checks:** none changed.
- **Smoke test:** E1, 93 s, exit 0. Outputs are identical.
- **Verdict:** safe. It only changes results with several areas, which can't be run
  end to end.

### Step 28: suspected #28, `Stock[[1]]$Nhist` in `HybridA`/`Hybrid` (`RatpackR.R:198-199, 279-280`)
- **Change:** `Stock[[Istock]]$Nhist` (4 references, used with `Initial.Eqn=T`).
- **Checks:** none changed.
- **Smoke test:** E1, 90 s, exit 0. Outputs are identical (single stock).
- **Verdict:** safe; it only matters for multi-stock runs where stocks have different `Nhist`.

### Step 29: suspected #29, `HybridA` NaN when every area is closed (`RatpackR.R:213`), now confirmed
- **End-to-end test:** a copy of Silver.warehou with its only area closed in 2026
  (`#Spatial:N_Closed_areas 1`, `1 2026 2026`; `Temp/ClosedInputs/`):
  - **old code:** the run stops with `Error in if (Cat.H2[Iarea, Ifleet] > 0) : missing value
    where TRUE/FALSE needed`, from `Bvul/sum(Bvul)` = 0/0. **This upgrades #29 to confirmed;
    closed areas crash the run.**
  - **fixed code:** the run completes (E1). The 2026 TAC is still set (6054 t), but the catch
    is about 0 (5.7e-16 t), because no area is open.
- **Change:** `if (sum(Bvul) > 0) Bvul <- Bvul/sum(Bvul)`. A fleet with every area closed
  takes no catch.
- **Checks:** none changed.
- **Smoke test:** E1, 89 s, exit 0. Outputs are identical.
- **Verdict:** safe; closed-area scenarios now run.

### Step 30: suspected #30, `Fout` undefined if `#MSY` is not 2 or 3 (`RatpackR.R:386`)
- **Test:** a copy of Silver.warehou with `#MSY 1` (`Temp/MSY1Inputs/`):
  - **old code:** stops with `object 'Fout' not found`;
  - **fixed code:** stops with `#MSY in the .OM file must be 2 (F at SPR target) or 3 (F at SSB
    target); found 1`.
- **Change:** a `stop()` with that message, added after the two `if` lines.
- **Checks:** none changed.
- **Smoke test:** E1, 92 s, exit 0. Outputs are identical.
- **Verdict:** safe; it only improves the error message. All current inputs use `#MSY 3`.

### Step 31: suspected #31, `SPR_ref` uses year-1 M and fecundity (`RatpackR.R:824, 871`)
- **Change:** `M[Isex,Iage,Iyear]` and `Fecundity[,Iyear]`, so the reference points use the
  biology of the year being evaluated, consistent with the selectivity already used.
  **Design choice for André:** the alternative is to keep year-1 (unfished-era) biology
  deliberately.
- **Effect:** `SPR_ref` only feeds the `TrueRBC` performance metric (`Project.One.Ahead`);
  it does not affect management.
- **Smoke tests:** E1 93 s and E2 98 s, both exit 0. Outputs are identical: Silver.warehou's
  M and fecundity in the reference year equal year 1, and `TrueRBC` is 2504.2 t before and
  after. The fix changes results only when M or fecundity vary over time (heatwave M, M
  links, time-varying growth).
- **Checks:** none changed.
- **Verdict:** safe; it only matters with time-varying biology.

### Step 32: suspected #32, `<-` on globals (`RatpackR.R:1761`, `Assessment.R:1816`)
- **Change:** `General$Nsim <<- 1` and `Stock[[Istock]]$TheTACs[1] <<- 0`. Both made local
  copies of the global objects.
- **Tests:** `Estimation.test = 0` (the only mode that sets `TestCase` and so
  `General$Nsim <- 1`) was run before and after the fix: outputs are identical. E1, 94 s,
  exit 0, is identical too. The heatwave TAC closure (`Close.in.MHW`) is not used by the
  current inputs.
- **Checks:** none changed.
- **Verdict:** safe. Results are the same; the global objects now hold what the code intended.

### Steps 33–34: suspected #33 and #34, no change (by decision)
- **#33** (TAC roll-over leaves slot 50 unchanged): slot 50 is beyond any projection length
  in use, so it is harmless. Left as is.
- **#34** (`DoRun` stops after 1 simulation unless `Estimation.test >= 90`): André's
  intended development behaviour. Left as is; it is documented in `docs/cloud_setup.md`.

### Step 35: suspected #35, multi-area data generation in `DataGen` (`DataGen.R:51-57, 170-175`)
- **Change:**
  - discard data use the total and retained catch summed over the biological areas in the
    assessment area (`Use`), instead of indexing biological areas by the assessment-area
    number;
  - CAA expected values are summed over `Use` instead of using `Iarea` left over from an
    earlier loop (the last area only).
- **Not changed:** `Write_data` still writes discard data without an area split
  (`Assessment.R:172`). Fixing it needs an area column in `DiscardData`, a data-structure
  change for André.
- **Smoke tests:** E1 99 s and E2 99 s, both exit 0. Outputs are identical; the discard path
  is exercised because Silver.warehou has discard data.
- **CAA branch:** a copy with CAA samples for fleet 1 in 2015–2019 (`Temp/CAAInputs/`). Old and
  new code both completed and wrote **127 CAA rows**; the SS `data.dat` files are
  **identical** (single area).
- **Side observation for #36:** these deterministic CAA rows are not proportions. A sample
  of size 1 has observations summing to about 5, and one of size 2 about 57.
- **Checks:** none changed.
- **Verdict:** safe; it only changes results with several areas per assessment area.

### Step 36: suspected #36, deterministic age/CAA observations not normalised (`DataGen.R:129, 184, 243`)
- **Change:** `Observed <- Nsamp*Expected/sum(Expected)` for marginal ages, CAA and
  predator ages, as is already done for lengths (line 80).
- **Smoke tests:** E1 92 s and E2 105 s, both exit 0.
  - E1 (no estimation) is identical.
  - E2 (estimation): parameter estimates change by at most 1.9e-5 relative, the reported
    final maximum gradient (`ProjectMisc`) by 1%, and the estimated SSB series by 3.5e-6.
    The 2026 RBC (2627.52 t) and final TAC (1932.77 t) are **identical** to 2 dp.
  - This confirms that SS normalises compositions, so the old scaling only nudged the
    optimiser path.
- **Checks:** none changed.
- **Verdict:** safe; the data files are now proportions times sample size, as intended.

### Step 37: suspected #37, CAA re-uses the marginal-age seeds (`DataGen.R:164`)
- **Change:** `set.seed(...$CAA.seeds[...])`. `ReadIn.R` already builds `CAA.seeds`; they were
  never used.
- **Not changed:** `NsampLength = CAA.spec/2` can be fractional, and `rmultinom` silently
  truncates it (2.7 → 2, 0.5 → 0). At most half a fish is lost, so it is left as is and
  documented.
- **Smoke test:** E1, 94 s, exit 0. Outputs are identical; the standard inputs have no CAA.
- **CAA copy** (`Temp/CAAInputs/`): it completes with 127 CAA rows, as before, but **different
  length bins** are sampled, because of the separate stream. For 2016 the bins were 11, 15,
  16, 18, … and are now 16, 18, 19, 20, ….
- **Checks:** none changed.
- **Verdict:** safe. Marginal ages and CAA are now drawn independently.

### Step 38: suspected #38, environmental-index branch (`Assessment.R:318`), no change
- `if (Ind != Num.Pred+Ind)` depends only on `Num.Pred`, so the heatwave override is applied to
  *every* index when there are no predators. The intended condition (which index carries the
  heatwave signal) isn't clear from the code, so this is **left for André**.


