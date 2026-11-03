# ratpackR bug review

**Scope.** `RatpackR.R` and `R Inserts/` (`Assessment.R`, `DataGen.R`, `ReadIn.R`,
`WriteOut.R`, `SaveFiles.R`, `Model.cpp`, `Utils.cpp`), plus drift in `R Inserts/Parallel/`.
The review is of upstream `main` at `e57b8ca`. **No bug has been fixed**; this document only
reports. Line numbers refer to this branch. They match upstream except in
`R Inserts/Assessment.R`, where lines from 1756 on are 2 higher, because of the
platform-dependent SS call added for Linux.

**Status labels.**
- **Confirmed (test)**: reproduced by `docs/bug_checks.R` (check ID in brackets) or by the
  Linux smoke runs. Re-run with `Rscript docs/bug_checks.R` (about 30 s).
- **Confirmed (inspection)**: unambiguous from the code, not exercised by a test.
- **Suspected**: probably wrong, but it depends on intent or on configurations not run here.

**Severity.**
- **High**: wrong numbers or a crash in configurations the current inputs or run streams use.
- **Medium**: wrong or crashing in documented options that the current inputs do not use
  (multi-area, multi-stock, Tier 4b, `CatchType` 3, and so on).
- **Low**: cosmetic, diagnostic-only, latent, or a robustness issue.

**Fix experiments (branch `bugfix-experiments`).** Bugs #1–#16 and #18 have been fixed one at a
time there and regression-tested; see `docs/bugfix/bugfix_log.md`. No fix broke another part
of the code. #17 (the parallel copies) is not attempted, and the Low items are not started.
Original code: branches `linux-portability` and `bug-review`.

---

## Summary

| # | Sev. | Where | Problem | Status |
|---|---|---|---|---|
| 1 | High | `ReadIn.R:1730` | `FixedCosts` is read from a 5th column that does not exist, so it is NA; Cost and Profit are NA in every output (probably a feature in development) | Confirmed (test B02, smoke runs) |
| 2 | High | `RatpackR.R:24-29` | `SetBuffer`: the default buffer is computed and then overwritten, so it is never applied | Confirmed (test B01) |
| 3 | High | `Assessment.R:1844` | The SS clean-up block can never run (`!Estimation.test %in% 99` after an early return for `< 99`); about 11 MB is left per assessment | Confirmed (smoke run, `Estimation.test = 99`) |
| 4 | High (multi-stock) | `RatpackR.R:1314` | Allocation loop variable `Istocks`, but the body uses `Istock`; only the last stock is re-allocated | Confirmed (test B09) |
| 5 | High (multi-stock) | `RatpackR.R:82` | PGMSY divides by the primary stock's recent catch by fleet; zero catch gives NaN (crash) or Inf (TAC set to 0) | Confirmed (test B14) |
| 6 | Medium | `RatpackR.R:1343,1364` | `matrix(TACs[Istock,,,1], byrow=T)` scrambles fleets when `NassArea > 1` | Confirmed (test B08) |
| 7 | Medium | `RatpackR.R:831-863` | `SPR_ref` ignores movement (wrong target area) and sums catch for the last area only | Confirmed (test B10a, B10c) |
| 8 | Medium | `RatpackR.R:1001-1013` vs `563-582` | Initial equilibrium uses movement at age a-1; the projection uses age a | Confirmed (test B10b) |
| 9 | Medium | `Assessment.R:698` | A steepness bias multiplier > 0 is ignored when the EM `.ctl` is written | Confirmed (test B05) |
| 10 | Medium | `ReadIn.R:1004-1006`, `RatpackR.R:1146` | Early-R0 block end stored as `.end.yrs` but read as `_end_yrs` | Confirmed (test B04) |
| 11 | Medium | `ReadIn.R:1655-1679` | Catch-bias rows: every fleet uses fleet 1's row; the final segment is not filled | Confirmed (test B03a, B03b) |
| 12 | Medium | `Assessment.R:2231` | Tier 4b compares CPUE with the limit *multiplier* (partial `$` matching) | Confirmed (test B06) |
| 13 | Medium | `DataGen.R:111` | `Stock[[Iarea,Istock]]` crashes for discard-age data | Confirmed (test B07) |
| 14 | Medium | `RatpackR.R:1255` | `TAC.management = "No"` uses an undefined or 2-D `TACsOrig` with 3 subscripts | Confirmed (test B11) |
| 15 | Medium | `RatpackR.R:1731`, `ReadIn.R:1085` | `CatchType` 3: `F.Selex.Inp` is all zeros and is indexed with 2 subscripts | Confirmed (test B12) |
| 16 | Medium | `Assessment.R:2126` | Tier 4a `map=list(logr=...)` (should be `logR`) crashes when `EstR="No"` and `EstZ="Yes"` | Confirmed (test B20) |
| 17 | Medium | `R Inserts/Parallel/*` | The parallel versions are an older code base and do not work with the current `ReadIn.R` | Confirmed (test B17, inspection) |
| 18 | Medium | `RatpackR.R:552` | Catch-fleet index predictions multiply by age selectivity twice | Confirmed (inspection); no effect for current inputs (B19) |
| 19 | Low | `WriteOut.R:304` | `CatchDiscardl` typo; per-area discards are always written as 0 | Confirmed (smoke output) |
| 20 | Low | `Assessment.R:1233` | Descending rec-dev bias ramp mixes calendar and model years (gives about 1) | Confirmed (test B13) |
| 21 | Low | `ReadIn.R:1245` | Re-seeding with the original `Seed` makes later random streams repeat earlier ones | Confirmed (test B16) |
| 22 | Low | `ReadIn.R:1335` | `LengthData` seed row is one column short | Confirmed (test B18, warning) |
| 23 | Low | `Assessment.R` `file.remove(..., showWarnings=F)` | `showWarnings` is not a `file.remove` argument; R tries to delete a file named `FALSE` | Confirmed (smoke warning) |
| 24 | Low | `WriteOut.R:463` | `Totals <- rep(0,35)` but each fleet block has 41 values | Confirmed (smoke warning) |
| 25-45 | Low / Suspected | various | see "Further findings" | mostly Suspected |

---

## High severity

### 1. `FixedCosts` read from a non-existent column; all costs and profits are NA
- **Where:** `R Inserts/ReadIn.R:1730`; the writer is `R Inserts/SaveFiles.R:393`; used in
  `RatpackR.R:631` and `Model.cpp:274`.
- **Qualification (Paul):** this is probably a placeholder for a feature still in development
  (fixed costs per fleet), added to the reader before the input writer and input files were
  updated. If so, the defect is the half-added input that turns Cost and Profit into NA, not
  wrong economics. The suggested fix (default to 0 when the value is absent) keeps the
  feature available once 5-column inputs exist.
- **Trigger:** any run. Every `.OM` file in the repository has 4 numbers per fleet in
  `#Econ_parameters` (`1 1 1 1  # Fleet1`), as `SaveFiles.R` writes them. Column 5 is the
  comment character `#`.
- **What goes wrong:** `as.numeric("#")` gives NA (the `NAs introduced by coercion` warning
  in every run). `Cost = (Days*CostPerDay + NA)/1000` is NA, so `Cost` and `Profit` are NA in
  `ProjectAll_*.Out`, `ProjectFleet*.Out` and `ProjectIns_*.Out`. The smoke run gives
  `Revenue 0.059, Cost NA, Profit NA`. In `Do.Insurance`, `Project()` returns NA profits and
  `if (NetLoss > 0 & ProbCME <= Delta)` stops with *missing value where TRUE/FALSE needed*
  (B02b). No current input switches insurance on, so only the output columns are affected now.
- **Fix:** default `FixedCosts` to 0 when column 5 is missing or non-numeric. For example,
  `fc <- suppressWarnings(as.numeric(AllInput[Index+Ifleet,5])); if (!is.na(fc)) StockDetails$FixedCosts[Ifleet] <- fc`.
  Also make `SaveFiles.R` write 5 values (`1 1 1 1 0`).

### 2. `SetBuffer` throws away the default buffer
- **Where:** `RatpackR.R:24-29`.
- **Trigger:** any Tier 1 TAC with `#Buffer_specifications:Default` below 1.
  `Inputs Buffer/Silver.warehou.EM`, the buffer-study input, has `Default 0.9`, `Minimum 0`,
  `Stale_rate 0.075`.
- **What goes wrong:** `Buffer <- Stock$Ass$Buffer` is overwritten by
  `Buffer <- max(Min.Buffer, T.Buffer)`, so the 0.9 default never reaches the TAC. Only the
  stale-rate decline applies. Test B01: `Buffer=0.8, Stale.rate=0, Min.Buffer=0` returns
  TAC = 100 (expected 80).
- **Fix:** combine the two parts, for example
  `Buffer <- max(Stock[[Istock]]$Ass$Min.Buffer, Stock[[Istock]]$Ass$Buffer*T.Buffer)`
  (multiplicative) or `Buffer - Time*Stale.rate`, whichever André intended.

### 3. SS working folders are never cleaned up
- **Where:** `R Inserts/Assessment.R:1823` and `1844`.
- **Trigger:** every Tier 1 assessment. `Estimation.test < 99` returns early at line 1823.
  For `Estimation.test == 99`, the condition `!Estimation.test %in% c(99) & (Clean.up=="Default" || ...)`
  is FALSE, so the block that deletes `SS.exe`/`ss3`, `echoinput.sso`, `CompReport.sso`,
  `covar.sso`, `ss3.par` and so on never runs. The `Clean.up=="Full"` block that follows does
  run for 99.
- **What goes wrong:** each `SS_Sim_*` folder keeps about 11 MB, including a 7 MB copy of the
  executable. This was measured in the `Estimation.test=99` smoke run. A full run of
  100 simulations × 25 assessments uses about 27 GB of `Temp/`.
- **Fix:** probably `if (Estimation.test %in% c(99) & (...))`. Also note that `ss.log` is
  `ss3.log` when the executable is called `ss3` (on Linux).

### 4. Allocation loop uses `Istocks` but the body uses `Istock` (multi-stock runs)
- **Where:** `RatpackR.R:1314-1328`.
- **Trigger:** `General$Nstocks > 1` with `Relallocation` 1 or 2 (multispecies streams such
  as `RunCSIROM.R`).
- **What goes wrong:** the body indexes `Stock[[Istock]]` and `TACs[Istock,...]`, and
  `Istock` still equals `Nstocks` from the previous loop. Only the last stock's TAC is
  re-allocated, `Nstocks` times; the other stocks keep their unadjusted fleet split. The
  inner `1:Stock[[Istock]]$NassArea` also uses the last stock (test B09).
- **Fix:** `for (Istock in 1:Nstocks)`.

### 5. PGMSY divides by zero when the primary species had no recent catch on a linked fleet
- **Where:** `RatpackR.R:82` (`Proportion <- sum(TACs[Jstock,,Ifleet,1])/Catch.Comp[Ifleet,Jstock]`),
  with the comparison at line 98.
- **Trigger:** multispecies with PGMSY, where a fleet is linked to a primary stock that caught
  nothing on that fleet in the last 5 years.
- **What goes wrong:** if the TAC for that fleet is 0, `0/0` gives NaN and
  `if (Revised.catch > ...)` stops with *missing value where TRUE/FALSE needed*. If the TAC is
  positive, `x/0 = Inf`, so `TAC.reduction = 0` and the primary stock's TAC becomes 0 for every
  fleet. Test B14: TACs `c(100, 1)` become `c(0, 0)`.
- **Fix:** skip fleets with `Catch.Comp[Ifleet,Jstock] <= 0`, or carry over that fleet's TAC
  as in the `Jstock == 0` branch.

---

## Medium severity

### 6. TAC by fleet scrambled when there is more than one assessment area
- **Where:** `RatpackR.R:1343` and `1364`:
  `TAC.mat <- matrix(TACs[Istock,,,1], nrow=NassArea, ncol=Ncat_fleet, byrow=T)`.
- **Trigger:** `NassArea > 1`. It is harmless when `NassArea == 1`. It is also wrong when a
  stock's `NassArea` is smaller than `MaxAssArea`.
- **What goes wrong:** `TACs[Istock,,,1]` is already an area × fleet matrix in column-major
  order, so refilling it `byrow=T` mixes areas and fleets. Test B08: the true by-fleet TACs
  `11,22,33` come out as `12,31,23`.
- **Fix:** `TheCat <- colSums(matrix(TACs[Istock,1:NassArea,,1], nrow=NassArea))`.

### 7. `SPR_ref` ignores movement and sums catch for the last area only
- **Where:** `RatpackR.R:831-837` (age loop), `844-849` (plus group), `852-863` (catch).
- **Trigger:** `Narea > 1`, through `GetRefs`. This affects `TrueRBC` in `Project.One.Ahead`.
- **What goes wrong:**
  - (a) `Neqn[Iarea,...] += Move[Iarea,Jarea,...]*Ntemp` adds into the *source* area. With
    rows of `Move` summing to 1, no fish ever move. Test B10a: with one-way movement from
    area 1 to area 2, `SPR_ref` puts 0 fish in area 2; the projection rule gives 2.84.
  - (b) The plus-group matrix is not transposed (compare `Get.Initial`, line 1008).
  - (c) The catch loop uses `Iarea`, left at `Narea` after the previous loop, so only the last
    area's catch is counted. Test B10c: two identical areas give 0.182, and emptying area 2
    gives 0.
- **Fix:** use `Neqn[Jarea,Isex,Iage] <- Neqn[Jarea,Isex,Iage] + Move[Iarea,Jarea,Iage]*Ntemp`,
  use `t(Amove)` (as in `Get.Initial`), and wrap the catch calculation in
  `for (Iarea in 1:Narea)`.

### 8. Initial equilibrium uses a different movement age from the projection
- **Where:** `RatpackR.R:1003` and `1112` use `Move[Iarea,Jarea,Iage-1]`; `Project.One.Ahead`
  (`RatpackR.R:570`) uses `Move[Iarea,Jarea,Iage]`. `SPR_ref` (`836`) also uses `Iage-1`.
- **Trigger:** `Narea > 1` with age-dependent movement.
- **What goes wrong:** the "equilibrium" age structure that starts the OM is not the
  equilibrium of the OM's own dynamics. Test B10b: the maximum difference is 0.141 fish per
  recruit in a 4-age example.
- **Fix:** decide whether movement is indexed by age before or after ageing, and use the same
  index in all three places.

### 9. Steepness bias multiplier ignored when the EM control file is written
- **Where:** `R Inserts/Assessment.R:698`.
- **Trigger:** `#SS:parameter_Steep_bias` > 0 and ≠ 1 in the `.EM` file. `ReadIn.R:1889`
  reads it with default 1, like `#SS:M.est.Bias`.
- **What goes wrong:** only negative values (fixed h) are applied. Positive multipliers are
  silently ignored, unlike M (line 492). Test B05: bias 0.8, true h = 0.75, EM initial
  h = 0.75. This affects EM-misspecification scenarios for h.
- **Fix:** `Initial.val <- Ass$SR_Steep*Ass$SS_Steep_Bias; if (Ass$SS_Steep_Bias < 0) Initial.val <- -1*Ass$SS_Steep_Bias`.

### 10. Early-R0 multiplier block end: two spellings of one variable
- **Where:** `ReadIn.R:1004` sets `Early.R0.mult_end_yrs <- c(0,0)`; `ReadIn.R:1006` reads the
  input into `Early.R0.mult.end.yrs`; `RatpackR.R:1146/1148` test `Early.R0.mult_end_yrs`.
- **Trigger:** `#Early_R0Mult` with non-zero equilibrium catch (the "Doing initial catch" block
  of `Do.Project`). Morwong and P.cod use `#Early_R0Mult`, but both have zero equilibrium
  catch, so current runs are unaffected.
- **What goes wrong:** `Early.R0.mult_end_yrs[1]` is always 0, so the
  `exp(Early.R0.mult + EarlyDevs)` adjustment of the initial numbers never happens. Test B04:
  `_end_yrs` is (0,0) while `.end.yrs` holds (1,10).
- **Fix:** use one name, for example `Early.R0.mult.end.yrs` everywhere.

### 11. Catch bias: every fleet uses fleet 1's row, and the last segment is not filled
- **Where:** `ReadIn.R:1658-1678`.
- **Trigger:** `#Catch:Base_Bias` rows that differ between fleets, or values other than 1.
  Every current input has `3 1980 1 2026 1 2125 1` (no bias), so this is latent.
- **What goes wrong:**
  - (a) `Index2 <- Index+Ifleet` is computed but never used; every fleet reads row `Index+1`
    (test B03a).
  - (b) `if (YrN > General$Nproj+1)` compares a model-year index with `Nproj+1`, not
    `Nhist+Nproj+1`. The last value is then applied only from the final year, and years
    between the last break and the end stay at 1. Test B03b: the spec says 1.2 from 2000, but
    2010 has 1.0.
- **Fix:** read `AllInput[Index2, ...]` and compare with `Nhist+General$Nproj+1`.

### 12. Tier 4b uses the limit multiplier as the CPUE limit
- **Where:** `R Inserts/Assessment.R:2231`:
  `if (CpueAvg <= Stock[[Istock]]$Ass$Tier4b$Cpue_lim)`.
- **Trigger:** `Ass_Basic:Type Tier_4b` (no current input uses it).
- **What goes wrong:** there is no element `Cpue_lim`, so `$` partially matches
  `Cpue_limit_mult` (for example 0.4; test B06). The zero-catch branch is only taken when the
  average CPUE falls below 0.4 in CPUE units. Otherwise `mult = (CpueAvg-Cpue.limit)/(...)` can
  be negative, giving a negative RBC.
- **Fix:** `if (CpueAvg <= Cpue.limit) mult <- 0`. Also consider capping `mult` at
  `max(0, ...)`.

### 13. `DataGen` discard age compositions crash
- **Where:** `R Inserts/DataGen.R:111`: `Stock[[Iarea,Istock]]$CatchAtAgeRet[Ifleet,,,Year]`.
- **Trigger:** any `Age.spec[,2,,] > 0`, that is, discard age data.
- **What goes wrong:** *incorrect number of subscripts* (test B07).
- **Fix:** `Stock[[Istock]]$CatchAtAgeRet[Iarea,Ifleet,,,Year]`.

### 14. `TAC.management = "No"` path crashes
- **Where:** `RatpackR.R:1255`: `TACsAdjust1[Istock,IassArea,,] <- TACsOrig[Istock,IassArea,]`.
- **Trigger:** an EM with TAC management off.
- **What goes wrong:** `TACsOrig` only exists inside the equilibrium-catch block, as a
  `Ncat_fleet × 50` matrix (line 1076). It is either not found, or *incorrect number of
  dimensions* (test B11).
- **Fix:** build the by-fleet TAC directly from `RBCsOrig`, for example with the fleet split
  used in `AdjustTACS`.

### 15. `CatchType` 3 (input F) is not usable
- **Where:** `ReadIn.R:1085-1090` (`F.Selex.Inp` all zeros, with the fill commented out
  "AEP FIX"); `RatpackR.R:1731` (`F.Selex.Inp[,Ifleet]` on a 3-D array).
- **Trigger:** `#Catches:Project_type 3`.
- **What goes wrong:** the historical F is 0. In multispecies runs `ReviewFsolver` stops with
  *incorrect number of dimensions* (test B12).
- **Fix:** restore the fill from `OM.obj$Fleet.F.data`, and use `sum(F.Selex.Inp[,Ifleet,])`.

### 16. Tier 4a `map` names a parameter that does not exist
- **Where:** `R Inserts/Assessment.R:2126`: `map <- list(logr=factor(NA))`.
- **Trigger:** `#Tier_4a:EstR No` with `#Tier_4a:EstZ Yes`. The current Tier 4a inputs use
  `EstR Yes / EstZ No`.
- **What goes wrong:** RTMB stops with *Names in map must correspond to parameter names*
  (test B20).
- **Fix:** `logR`.

### 17. `R Inserts/Parallel/` has drifted from the main code
- **What:** `Parallel/RatpackR.R` is an older engine (2 400 lines with differences). It has no
  `SetBuffer`, no `Indicator.species.TACS`, no `ReviewFsolver`, no data delays
  (`Delay.*`), no `Relallocation`, and no `TACsStep` diagnostics. It has its own older
  `Read.General.File` but sources the *current* `R Inserts/ReadIn.R`, `Assessment.R` and so on.
  The main `Run_Assessment` then reads `General$Delay.Index`, which is NULL, so delays are
  silently ignored.
- `Parallel/Assessment.R` (about 500 differing lines) is older still:
  - It treats `Is_discard`, `Is_index`, `Is_age` and `Is_CAA` as logical, but the current
    `ReadIn.R` stores `"Yes"`/`"No"` strings. `sum(Is_discard)` fails (test B17).
  - It uses `Data$IndexData` rather than `IndexData.Used`, so data delays are ignored.
  - It has old `Ass$BDM_*` names (now `Ass$Tier4a$*`) and no `Run_Tier4b`.
  - It has no Richards growth, no M or steepness bias, `max F` hard-coded to 4, male
    selectivity patterns forced to 0, and an `r/2` in `FABC1` instead of `Ftargt1`.
- It also needs a global `n_cores`.
- **Fix:** regenerate the parallel versions from the current main files, keeping only the
  `foreach` wrapper and the `on.exit(setwd(Path))` change. Better still, make `DoRun` take
  `UseParallel` so there is one code base.

### 18. Catch-fleet CPUE predictions apply age selectivity twice
- **Where:** `RatpackR.R:552`:
  `BioPreds += SelexAge[...] * SelRetWghtAge[...] * N * (1-exp(-Z))/Z`.
  `SelRetWghtAge` already includes `SelexAge` (`ReadIn.R:969`). For surveys, line 554 uses
  `SelWghtAge`, which does not.
- **Trigger:** indexed catch fleets with age-based selectivity strictly between 0 and 1. For
  Silver.warehou, and in a scan of all `.OM` files, the indexed catch fleets have 0/1 age
  selectivity (length-based selex), so there is no effect at present (B19).
- **Fix:** drop `SelexAge` from line 552.

---

## Low severity (confirmed)

19. **`WriteOut.R:304` `CatchDiscardl` typo.** `Stock[[Istock]]$CatchDiscardl` is NULL, so the
    `Discard_catch_Area` column of `ProjectFleetArea_*.Out` is always 0. In the smoke run its
    total is 0 while `ProjectAll` shows 6 792 t of discards. Fix: `CatchDiscard`. Also line 316,
    `Stock[[Istock]]$Full`, works only through partial matching of `FullF`.
20. **`Assessment.R:1233`, descending recruitment bias ramp in the `.par` writer.**
    `(Year+last_full+YrOffset - Iyr)/(end_ramp - last_full + YrOffset)` mixes calendar years
    (`Iyear`) with model years (`Iyr`), and adds `YrOffset` to a difference. It gives about
    0.995 instead of a ramp from 1 to 0 (test B13). It only affects starting values when
    `Use.par` is on, and only for years where the bias is applied; for Silver.warehou the
    branch is never reached. Fix:
    `(Year+last_full+YrOffset - Iyear)/(end_ramp - last_full)`.
21. **`ReadIn.R:1245`, random-number streams re-used.** The discard deviations call
    `set.seed(Seed)`, the stock's original seed, and so reset the `NextSeed` chain. Every
    later stream (length, age and CAA seeds, catch devs) repeats an earlier stream. For example,
    the age-sample seeds are built from the same uniforms that decide catastrophic-M events
    (test B16). Fix: `set.seed(NextSeed)`.
22. **`ReadIn.R:1335`, `LengthData` seed row.** It has `6+Nsex*Nlen` columns, but `DataGen`
    appends `7+Nsex*Nlen`, which causes an `rbind` warning and a recycled dummy row (test B18).
    The age and CAA seeds use the right width. Fix: `rep(0,7+Nsex*Nlen)`.
23. **`file.remove(x, showWarnings=F)`** (`Assessment.R:1781`, `1840-1842`, `1854-1859`).
    `file.remove` has no such argument, so `FALSE` is treated as a second file name (smoke
    warning *cannot remove file 'FALSE'*). Fix: `if (file.exists(x)) file.remove(x)`.
24. **`WriteOut.R:463`.** `Totals <- rep(0,35)` but each fleet block has 5 + 3 + 33 = 41
    values; it raises 48 warnings per simulation. The sums come out correct through recycling.
    Fix: `rep(0,41)`.

---

## Further findings (Low unless noted; Suspected unless noted)

25. **`RatpackR.R:1303`.** `if (Stock[[Istock]]$Ass$TAC.management=="Yes")` is evaluated
    before its `for (Istock ...)` loop, so it uses the last stock's flag (inspection).
26. **`RatpackR.R:1311`.** `TACsStep[6,Iyear] <<- Stock$TACs[Iyear]` records the *previous*
    TAC; `Stock$TACs[Iyear]` is set later, at line 1393. Use `sum(TACs[Istock,,,1])`
    (inspection; diagnostic only).
27. **`RatpackR.R:1147-1157` (multi-area).** `EarlyDevs[1:MaxAge]`, `EarlyDevs[1]` and `R0[1]`
    use linear indexing on `[Narea, …]` matrices, giving area 1 values (or the wrong cells) for
    every area. Use `EarlyDevs[Iarea,]` and `R0[Iarea,1]`. The same problem occurs in
    `Assessment.R:766,1250` (`Finitial[Ifleet]` on an area × fleet matrix) and
    `Assessment.R:1238` (`Rec_devs[Iyr]`).
28. **`RatpackR.R:198,279`.** With `Initial.Eqn=T`, `HybridA`/`Hybrid` use
    `Stock[[1]]$Nhist` for every stock.
29. **`RatpackR.R:212`.** `Bvul/sum(Bvul)` gives NaN if every area is closed to a fleet that
    has a catch. `Hybrid` (line 305) divides by `Zrate`, which is 0 if M = 0 at some age and
    there is no F.
30. **`RatpackR.R:384-385`.** `Fout` is undefined if `#MSY` is neither 2 nor 3. All current
    inputs use 3.
31. **`RatpackR.R:822,867`.** `SPR_ref` uses `M[,,1]` and `Fecundity[,1]` (year 1) with
    selectivity for `Iyear`. With time-varying M (heatwaves), the reference points use
    year-1 M.
32. **`RatpackR.R:1757` and `Assessment.R:1816` (misuse of `<-` on globals).**
    `General$Nsim <- 1` and `Stock[[Istock]]$TheTACs[1] <- 0` create *local copies* inside
    `DoRun` and `Run_Tier1a`; the global objects are unchanged. They work only because the
    local copy is what is used next. Use `<<-`, or avoid relying on it.
33. **`RatpackR.R:1266`.** The TAC roll-over shifts by one year but leaves slot 50 at its old
    value.
34. **`RatpackR.R:1849`.** `DoRun` returns after the first simulation unless
    `Estimation.test >= 90`. This is intended for development, but easy to forget.
35. **`DataGen.R:51-56`.** Discard data use `CatchTotal[IassArea,...]`, indexing biological
    areas by the *assessment*-area number (`Use` is computed but not used). `DataGen.R:172-174`:
    conditional age-at-length uses `Iarea`, left from the loop at line 148, which is only the
    last area of the assessment area. `Assessment.R:172`: discard data are not split by
    assessment area. These matter only for `NassArea`/`Narea > 1`.
36. **`DataGen.R:129,182,241`.** Deterministic age and CAA observations are
    `Nsamp*Expected` with `Expected` *not* normalised (length data are normalised at line
    80). SS normalises compositions, so the effect is small (inspection).
37. **`DataGen.R:164-165`.** CAA uses the *age* seeds (the same stream as the marginal ages),
    and `NsampLength = CAA.spec/2` can be fractional.
38. **`Assessment.R:318`.** `if (Ind != Num.Pred+Ind)` depends only on `Num.Pred`. With no
    predators, the heatwave override (`Env.Val <- 1`) is applied to every environmental index,
    not to a specific one.
39. **`Assessment.R:1350`.** `forecast.ss` is opened with `append=T` (the starter, data and
    control files are not). A reused folder would get two forecast files concatenated.
    `Assessment.R:1405`: `2019 # FirstYear for caps` is hard-coded; it probably should be
    `Year+YrOffset+1`.
40. **Tier 4a (`Assessment.R:1920,1933`).** `B0(t)` is a function-call typo; the branch is dead
    because `IsDymB0=0`. `dnorm(log(C), ...)` is -Inf when any historical catch is 0.
    **Tier 4b (`2223,2235`).** It uses true OM total catch rather than observed catch, and a
    hard-coded `/0.48`.
41. **Insurance (`Assessment.R:1504`, `Model.cpp:258`).** The SPR target is hard-coded to
    0.41. `Project()` gives each sex the full `R0` (doubles recruitment when `Nsex=2`); the
    author's "Need to fix for multiple sexes" note applies.
42. **Predator module (`RatpackR.R:531-543`, `DataGen.R:195-248`, `ReadIn.R:1127`).** It is
    unfinished: there is a deliberate `AAAA` stop, an undefined `sex`, and
    `ConsumpTotal`/`CompumpAtAge` dimensions that do not match between files.
43. **`ReadIn.R:547-614`.** `CVoption` 3 and 4 are not implemented, so the SD stays 0 and the
    ALK becomes a step function. `CVoption` 0 extrapolates the CV beyond `LenA2`.
44. **Hard-coded 50s.** There are 50 forecast years (`Assessment.R:1247,1367`), and the
    `TACs`/`RBCsOrig` arrays have 50 slots (`RatpackR.R:1210-1212`). If `ForeCatch_` does not
    return 50 values, `RBCsOrig[Istock,IassArea,] <- Run_Assessment(...)` fails (*not a multiple
    of replacement length*). `Utils.cpp`, `Project2` and `GetRecruit` (`Model.cpp`) are not used
    anywhere. `GetRec`'s Ricker branch uses an undefined `SSB0` (dead code, `SR_type=2`).

45. **Tier 4a gives RBC = 0 for P.cod** (found during the fix tests). This happens with both
    P.cod's own `EstR Yes/EstZ No` and `EstR No/EstZ Yes`, with `sdreport` warnings
    (`NaNs produced`). True 2025 depletion is 25%, between `alpha` (0.20) and `beta` (0.35),
    so the RBC should be positive. The fit may underestimate depletion, or the Hessian may be
    singular. Suspected; needs a closer look.

## Checks that passed

- The SS `.par` file written by `Write_ctl` is read back exactly: with no estimation, all 147
  values in `ss3.par` equal the input `ss3a.par`.
- The ageing-error matrix orientation (`[obs, true]`) matches its use in `DataGen`
  (`A %*% expected`).
- The VB length-at-age recursion, the ALK, the Beverton–Holt forms (`GetRec`,
  `Project.One.Ahead`) and the AR(1) recruitment deviations are consistent with their stated
  formulas.
- `Write_forecast`'s 50 forecast years matches the 50 `Fcast_recruitments` written to the
  `.par` file.
