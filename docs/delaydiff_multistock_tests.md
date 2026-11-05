# Tier_DD (delay-difference EM) tests on nine SESSF stocks

Branch `claude/elegant-feynman-9zx3v3` (based on `paul/delaydiff-em` at d372de8). Run on 4 Nov 2026 in a
Claude Code cloud container: Ubuntu, R 4.5.3 (conda-forge), r4ss 1.56.0, RTMB 2.0, Rcpp 1.1.2,
RcppArmadillo 15.6.2.1, set up with `setup_linux.sh` (3 min 14 s). Key numbers are also in
[`docs/results/tier_dd_multistock_2026-11-04.csv`](results/tier_dd_multistock_2026-11-04.csv).

## 1. Summary

| Result | Stocks |
|---|---|
| Completed: 4 Tier_DD assessments, 10 projection years, exit 0 | All 9: Morwong, Bight redfish, Blue grenadier, Deepwater flathead, Mirror dory, Pink ling, Tiger flathead, School whiting, Silver warehou |

- In the first round, Blue grenadier failed at its first assessment (negative variance from a 1-fish length comp). This is fixed in `Run_DelayDiff` (§4.1) and the stock now completes.
- Orange roughy east is excluded from these tests (Paul's decision, 4 Nov 2026). It has no length data, so it is not a candidate for this length-based EM (§4.2).
- Regression check after the fix: 7 of the other 8 stocks give byte-identical `Estimates` files. School whiting changes slightly (final-year depletion 0.292→0.293, 0.320→0.321, 0.515→0.518, 0.698→0.701), because comps with fewer than 3 occupied bins are now skipped.
- The Morwong cloud run matches the single-stock cloud run of 3 Nov exactly (the estimates file is byte-identical between repeat runs), and it matches the Windows result: all TACs 0; estimated depletion 0.019 in 2020.
- The EM depletion estimates are within about ±0.15 of the OM for Deepwater flathead, Mirror dory and Silver warehou (last three assessments). They are biased high for Bight redfish and Pink ling, and biased low for Morwong, Tiger flathead and School whiting (§3).

## 2. What was run

- **Inputs.** `MISC HCR/make_DD_inputs.R` builds `Inputs DD/<Stock>.{OM,EM,OM.SAV,EM.SAV}` and `General_<Stock>.OM` from `Inputs CSIRO/` (Bight redfish, Blue grenadier, Deepwater flathead, Mirror dory, Pink ling), `Inputs CSIROM/` (Tiger flathead, School whiting; single-stock general files) and `Inputs Buffer/` (Silver warehou). The OM is copied unchanged. The EM is switched to `Tier_DD` and gets a `#Tier_DD:` block. The general file is set to 1 simulation, 10 projection years and an assessment every 3 years, as for Morwong. Redfish was not tested, because `Inputs CSIRO/` has no `Redfish.OM`. Orange roughy east is excluded (§4.2).
- **Priors from the OM biology** (first sex, i.e. females, because the two sexes can differ a lot: Mirror dory k = 0.19 and 1.01). This recipe reproduces the hand-set Morwong values:
  - `kage` = growth A_min (at least 1);
  - `Tauk` = VB length at `kage` (SD 7 %);
  - `Linf_init` = VB L∞ derived from L(A_min), L(A_max) and k, or L(A_max) when A_max = 999;
  - `Rho` = exp(−k) (SD 0.05); `Surv` = exp(−M) (SD 0.03);
  - `Sigtau` = CV × mid length; `MaxLen_g1` = Tauk + (L∞ − Tauk)/3;
  - `beta_init` = (1 − 0.2/h)/0.8 (h = 0.75 for all, so 0.917, fixed);
  - `Entry` 0.4 (SD 0.15) and all the other options as for Morwong.
- **Data choices.**
  - CPUE index: the fleet with index data in the future and the most past index years.
  - Length comps: the fleet with future retained comps and the most past retained comps (`Len_Part 2`). If there is none, total comps are used, and failing those, nothing.
- **Run.** `RunStreams/RunDDStock.R <Stock>` (a copy of `RunDD.R` that takes the stock name), with `options(warn=1)`, 4 stocks in parallel.

| Stock | CPUE fleet | Length fleet (past comps) | kage | Rho | Surv | Tauk | L∞ | Sigtau |
|---|---|---|---|---|---|---|---|---|
| Morwong (hand-set) | 1 | 1 ret (—) | 3 | 0.79 | 0.861 | 21.45 | 35.5 | 3 |
| Bight redfish | 2 | 1 ret (20) | 8 | 0.934 | 0.900 | 19.7 | 42.5 | 4.5 |
| Blue grenadier | 2 | 4 ret (34) | 1 | 0.801 | 0.787 | 26.1 | 99.0 | 6.9 |
| Deepwater flathead | 2 | 1 ret (23) | 2 | 0.857 | 0.787 | 21.6 | 70.5 | 5.6 |
| Mirror dory | 1 | 1 ret (45) | 5 | 0.827 | 0.638 | 39.9 | 58.1 | 4.9 |
| Pink ling | 1 | 1 ret (33) | 2 | 0.868 | 0.795 | 43.8 | 121 | 7.2 |
| Tiger flathead | 1 | 5 ret (51) | 3 | 0.840 | 0.763 | 28.6 | 56.0 | 4.8 |
| School whiting | 3 | 1 ret (31) | 1 | 0.771 | 0.549 | 11.6 | 24.9 | 1.7 |
| Silver warehou | 1 | 3 ret (35) | 1 | 0.763 | 0.741 | 15.4 | 52.1 | 2.9 |

## 3. Results

Depletion at the last year of each assessment. EM = fished-group biomass relative to year 1 (`Depl.estimates`).
OM = SSB relative to the first model year, from `ProjectAll` (equal to the OM's `Total_Depletion` for every stock except Morwong; see §4.4).

| Stock | Run time | Assessment years | EM depletion | OM depletion |
|---|---|---|---|---|
| Morwong | 63 s | 2020, 23, 26, 29 | 0.019, 0.025, 0.033, 0.042 | 0.050, 0.076, 0.108, 0.149 |
| Bight redfish | 50 s | 2021, 24, 27, 30 | 0.827, 0.798, 0.599, 0.564 | 0.634, 0.531, 0.409, 0.349 |
| Blue grenadier | 56 s | 2021, 24, 27, 30 | 0.742, 0.711, 0.578, 0.747 | 0.936, 1.001, 0.885, 0.809 |
| Deepwater flathead | 56 s | 2022, 25, 28, 31 | 0.275, 0.425, 0.560, 0.694 | 0.401, 0.482, 0.572, 0.681 |
| Mirror dory | 50 s | 2025, 28, 31, 34 | 1.046, 1.443, 0.978, 0.803 | 0.915, 1.755, 1.038, 0.791 |
| Pink ling | 73 s | 2025, 28, 31, 34 | 0.370, 0.717, 1.161, 1.044 | 0.375, 0.446, 0.484, 0.528 |
| Tiger flathead | 81 s | 2025, 28, 31, 34 | 0.116, 0.209, 0.394, 0.550 | 0.367, 0.495, 0.723, 0.759 |
| School whiting | 40 s | 2025, 28, 31, 34 | 0.293, 0.321, 0.518, 0.701 | 0.464, 0.646, 0.788, 1.290 |
| Silver warehou | 104 s | 2025, 28, 31, 34 | 0.170, 0.654, 0.735, 0.681 | 0.563, 0.671, 0.736, 0.999 |

Total TAC (t, summed over fleets) in each of the 10 projection years, under the placeholder HCR
(`Dlim` 0.2, `Dtarg` 0.48, `Htarg` 0.1):

| Stock | Years 1–10 |
|---|---|
| Morwong | 0 0 0 0 0 0 0 0 0 0 |
| Bight redfish | 1357 1237 1130 1398 1275 1166 999 917 786 1065 |
| Blue grenadier | 1447 1619 1676 2006 1935 1880 1666 1679 1693 1957 |
| Deepwater flathead | 33 127 199 182 204 225 235 252 265 594 |
| Mirror dory | 282 294 285 299 262 234 237 224 216 217 |
| Pink ling | 87 148 198 319 316 308 503 471 431 471 |
| Tiger flathead | 0 0 79 173 281 449 671 807 934 942 |
| School whiting | 96 263 314 181 286 332 331 373 402 405 |
| Silver warehou | 32 50 58 509 469 421 544 502 446 442 |

Notes:

- This is one simulation per stock, so these are single realisations, not performance statistics.
- With 1 simulation and an assessment every 3 years, the TAC is held between assessments. The changes within those 3-year blocks come from how ratpackR applies the TAC across fleets, not from the EM.
- Optimiser: one "Tier_DD: max gradient 0.0139, false convergence (8)" message (Silver warehou). All other fits had max gradient < 0.01.
- The HCR is exercised for the first time: Tiger flathead's first assessment (0.116 < `Dlim`) gives 0 TAC, and the others give positive TACs.

## 4. Issues found

1. **Blue grenadier: all fits fail (NaN). Fixed.** One retained length comp of fleet 4 contains a single fish (n = 1, one non-empty bin). With 2-cm bins, Sheppard's correction makes its variance negative (0.0 − 2²/12 = −0.333). Then `sqrt(L2o/n)` in the length-moment likelihood (`R Inserts/DelayDiff.R`, `f_dd`) is NaN, so every start fails and `Run_DelayDiff` stops with "all fits failed". Suggested fix in `Run_DelayDiff`: skip comps whose corrected variance is ≤ 0, or whose sample has fewer than a minimum number of fish (for example n < 10) or occupies fewer than 3 bins. **Applied:** `Run_DelayDiff` now skips comps with fewer than `MinBins` occupied bins (new option, default 3), a stated sample size below `MinNsamp` (new option, default 0 = off, because Morwong's EFNs are 5–45), or a corrected variance ≤ 0. Blue grenadier now completes. Its EM depletion is 0.58–0.75 against an OM of 0.81–1.00, i.e. biased low.
2. **Orange roughy east: no length data; excluded.** It has age data only, so `Data$LengthData.Used` is not a matrix, and `Run_DelayDiff` stopped with `Error in LD[, 1]: incorrect number of dimensions`. The stock is now excluded from the Tier_DD tests. `Run_DelayDiff` keeps a guard (if `LD` has no dimensions, no comps are used) so that a stock without length data fails gracefully rather than with an indexing error.
3. **`Inputs CSIROM/*.Sav` is not found on Linux.** `SetSpec` (`R Inserts/ReadIn.R`) loads `<Stock>.OM.SAV`, but `Inputs CSIROM/` spells the files `.OM.Sav`. `RunCSIROM.R` would fail on Linux for the same reason. The generator copies them as `.SAV`. A permanent fix is to rename the files in `Inputs CSIROM/` (a rename only, so it's safe for upstream merges), and it belongs with the `linux-portability` changes.
4. **The OM's `Total_Depletion` for Morwong is not SSB/SSB(1915).** In `ProjectAll`, Morwong's `Total_Depletion` in 2020 is 15.98 %, but SSB(2020)/SSB(1915) is 0.050 (the 0.05 quoted in `docs/delaydiff_em.md`). The OM starts above SSB0 (`#Early_R0Mult 1.17`), so `Total_Depletion` uses a different reference than year 1. For the other stocks the two are equal. This matters for remaining-work item 2 in `docs/delaydiff_em.md` (which quantity to compare the EM with).
5. **Recurring warnings from the main code, not Tier_DD.** These occur for every stock:
   - `Totals + Outputs` "longer object length is not a multiple…" (`R Inserts/WriteOut.R` lines 294, 317, 479; 54–268 times per run);
   - `SetSpec` "NAs introduced by coercion" (6–27 times, while reading the inputs);
   - one `rbind(Stock[[Istock]]$Data$LengthData, Vec1)` column-mismatch warning.

   They do not stop the runs, but the `WriteOut.R` recycling may make some summary totals wrong. Worth checking with André.
6. **EM bias pattern** (one realisation, so this is indicative only).
   - Biased low (more pessimistic than the OM): Morwong, Blue grenadier, Tiger flathead, School whiting, Silver warehou in its first assessment.
   - Biased high (more optimistic): Bight redfish, and Pink ling after its first assessment (EM > 1 by 2031).
   - Possible causes: generic priors (`Entry` 0.4 for every stock, `kage` = growth A_min, which is 8 for Bight redfish and 1 for four stocks), effort derived from one CPUE series, and comps from one fleet. Pink ling and Mirror dory are 4-area OMs whose catches are summed into one fishery.

## 5. Suggested next steps

1. (Done) Fix §4.1 in `Run_DelayDiff`; exclude Orange roughy east (§4.2).
2. (Done, §7 and §8) Run 20 simulations per stock, and compare with Tier_1a on the same OMs. Tier_4a: not yet.
5. Look at the Tier_1a EM set-up for Blue grenadier and Silver warehou (§8: unbounded SS scale), and at Tiger flathead's EM growth ages (§8).
3. Check the sensitivity to `Entry`, `kage` and the choice of CPUE and length fleets for the biased stocks (Bight redfish, Pink ling, Tiger flathead).
4. Rename the `Inputs CSIROM/*.Sav` files (§4.3).

## 7. Twenty simulations per stock (5 Nov 2026)

Same inputs as §2 (`Inputs DD/`), but with `#Number_of_simulations 20`. The 20-simulation copies were made in `Temp/InputsDD20/` and run with `RATPACK_DD_INPUTS=Temp/InputsDD20/ RATPACK_DD_TAG=20 Rscript RunStreams/RunDDStock.R <Stock>`, so the results are in `Results/<Stock>.DD20/`. The seeds are ratpackR's defaults (`TheSeeds <- 1234`), so simulation 1 matches the single runs in §3.

All 9 stocks completed all 20 simulations (80 Tier_DD fits each, no errors), in 6–20 minutes per stock with 4 runs in parallel.
Per-simulation results are in [`results/tier_dd_20sims_by_sim.csv`](results/tier_dd_20sims_by_sim.csv) and the summary in [`results/tier_dd_20sims_summary.csv`](results/tier_dd_20sims_summary.csv).

Relative error (RE) = (EM − OM)/OM in the final-year depletion of each assessment. EM = fished-group biomass relative to year 1; OM = SSB relative to the first model year, from the same simulation. A1 and A4 are the first and fourth assessments. The ranges are 10th–90th percentiles over the 20 simulations.

| Stock | Median RE, A1 | Median RE, A4 | Median \|RE\|, all | EM depletion, A4 | OM depletion, A4 | Mean annual catch (t) | Gradient msgs |
|---|---|---|---|---|---|---|---|
| Morwong | −0.60 | −0.60 | 0.64 | 0.05 (0.04–0.10) | 0.15 (0.10–0.19) | 0 (all years 0) | 1 |
| Bight redfish | +0.36 | +0.43 | 0.48 | 0.43 (0.29–0.62) | 0.28 (0.22–0.60) | 1186 (950–1379) | 3 |
| Blue grenadier | −0.13 | −0.28 | 0.28 | 0.59 (0.43–0.75) | 0.82 (0.60–0.97) | 1899 (1636–2469) | 0 |
| Deepwater flathead | −0.28 | +0.01 | 0.17 | 0.64 (0.38–0.87) | 0.64 (0.46–0.81) | 315 (252–471) | 0 |
| Mirror dory | +0.12 | +0.19 | 0.15 | 0.97 (0.74–1.18) | 0.77 (0.63–1.06) | 264 (211–355) | 0 |
| Pink ling | −0.01 | −0.03 | 0.16 | 0.59 (0.40–0.82) | 0.62 (0.53–0.72) | 220 (67–383) | 4 |
| Tiger flathead | −0.70 | −0.20 | 0.51 | 0.54 (0.45–0.78) | 0.75 (0.53–1.12) | 479 (316–612); 18 % of years 0 | 7 |
| School whiting | −0.47 | −0.37 | 0.43 | 0.56 (0.33–0.90) | 0.88 (0.64–1.26) | 399 (295–666) | 4 |
| Silver warehou | −0.09 | +0.05 | 0.14 | 0.83 (0.63–1.16) | 0.75 (0.52–1.09) | 754 (490–942) | 5 |

Findings:

- **Close to unbiased** (median RE within ±0.1 by the fourth assessment, median |RE| ≤ 0.17): Deepwater flathead, Pink ling and Silver warehou. Pink ling's large positive error in the single run (§3) was one realisation; over 20 simulations it is unbiased.
- **Persistently pessimistic:** Morwong (−0.60), School whiting (−0.4), Blue grenadier (−0.1 to −0.3) and Tiger flathead, which is strongly negative at the first assessment (−0.70) and improves to −0.20 as data accumulate. Under the placeholder HCR, this gives zero catches for Morwong in every simulation and in 18 % of Tiger flathead's projection years.
- **Optimistic:** Bight redfish (+0.36 to +0.43; `kage` 8, the oldest entry age) and, mildly, Mirror dory (+0.12 to +0.19).
- **Optimiser:** 24 "max gradient > 0.01" messages over 720 fits (3 %), concentrated in Tiger flathead (7), Silver warehou (5), Pink ling (4) and School whiting (4).
- **Caveats:**
  - 20 simulations give a rough picture of bias, not precise quantiles.
  - The EM and OM quantities differ (fished-group biomass against SSB; §4.4 and `docs/delaydiff_em.md` remaining work 2), so part of each "bias" may be definitional, especially for stocks where selectivity and maturity differ.
  - The priors are generic (§2).

## 8. Tier_DD against Tier_1a, 20 simulations (5 Nov 2026)

Tier_1a (Stock Synthesis, `CodeBase/ss3_linux`) was run on the same OMs, seeds and settings: 20 simulations, 10 projection years, an assessment every 3 years. The inputs were copies of `Inputs DD/` with only `Ass_Basic:Type` switched to `Tier_1a` (in `Temp/InputsT1a20/`; results in `Results/<Stock>.DDT1a20/`). Both methods use the same historical OM realisation in each simulation (e.g. the Silver warehou OM SSB in 2025 is identical in the two runs). From the first TAC onward the trajectories differ, because each method sets its own TACs.

- Tier_1a: 8 of 9 stocks completed 20 simulations, in 8–152 minutes per stock (4 in parallel); Tiger flathead failed (see below).
- Files: [`results/tier_dd_vs_tier1a_20sims.csv`](results/tier_dd_vs_tier1a_20sims.csv) (comparison), [`results/tier1a_20sims_by_sim.csv`](results/tier1a_20sims_by_sim.csv) and [`results/tier1a_20sims_summary.csv`](results/tier1a_20sims_summary.csv).

How the columns are defined:

- **RE** is each method's error against the OM quantity it estimates:
  - Tier_1a: SS depletion SSB/SSB0 against OM `Total_Depletion`;
  - Tier_DD: fished-group biomass relative to year 1 against OM SSB relative to the first model year (as in §7).
- **Mean catch** is the median over simulations of the mean annual catch in the 10 projection years.
- **OM end depletion** is OM SSB/SSB0 (`Total_Depletion`) in the last projection year. It is the same measure for both methods, so it shows the outcome under each.
- The HCRs differ: Tier_1a uses the SESSF Tier 1 rule in the EM files (`#Tier_1:` F_48 target and B_48 target, inflection 0.35, F = 0 at 0.20, buffer 1.0); Tier_DD uses the placeholder rule (`Dlim` 0.2, `Dtarg` 0.48, `Htarg` 0.1). So the catch and outcome columns compare EM + HCR combinations, not the EMs alone.

| Stock | Method | Median RE A1 | Median RE A4 | Median \|RE\| | Mean catch (t) | OM end depletion | P(end < 0.2) |
|---|---|---|---|---|---|---|---|
| Morwong | Tier_1a | +0.15 | +0.03 | 0.13 | 183 (126–222) | 0.34 (0.24–0.49) | 0.05 |
| | Tier_DD | −0.60 | −0.60 | 0.64 | 0 | 0.52 (0.36–0.66) | 0.00 |
| Bight redfish | Tier_1a | +0.07 | −0.03 | 0.13 | 607 (512–738) | 0.54 (0.42–0.70) | 0.00 |
| | Tier_DD | +0.36 | +0.43 | 0.48 | 1186 (950–1379) | 0.28 (0.22–0.62) | 0.05 |
| Blue grenadier | Tier_1a | +2.36 | n/a (stock collapsed) | — | 10760 (9942–11437) | 0.00 (0.00–0.00) | 1.00 |
| | Tier_DD | −0.13 | −0.28 | 0.28 | 1899 (1636–2469) | 0.78 (0.56–0.92) | 0.00 |
| Deepwater flathead | Tier_1a | +0.15 | +0.01 | 0.20 | 1030 (827–1215) | 0.44 (0.29–0.59) | 0.05 |
| | Tier_DD | −0.28 | +0.01 | 0.17 | 315 (252–471) | 0.65 (0.48–0.83) | 0.00 |
| Mirror dory | Tier_1a | +0.03 | +0.29 | 0.25 | 1820 (1259–2237) | 0.32 (0.14–0.42) | 0.20 |
| | Tier_DD | +0.12 | +0.19 | 0.15 | 264 (211–355) | 0.81 (0.58–1.06) | 0.00 |
| Pink ling | Tier_1a | +0.24 | +0.31 | 0.30 | 668 (632–724) | 0.42 (0.35–0.48) | 0.00 |
| | Tier_DD | −0.01 | −0.03 | 0.16 | 220 (67–383) | 0.63 (0.54–0.76) | 0.00 |
| School whiting | Tier_1a | +0.14 | −0.09 | 0.25 | 2656 (1922–2999) | 0.53 (0.32–0.97) | 0.10 |
| | Tier_DD | −0.47 | −0.37 | 0.43 | 399 (295–666) | 0.92 (0.70–1.39) | 0.00 |
| Silver warehou | Tier_1a | +0.53 | −0.03 (after collapse) | 0.96 | 2738 (2058–3346) | 0.02 (0.01–0.07) | 0.95 |
| | Tier_DD | −0.09 | +0.05 | 0.14 | 754 (490–942) | 0.80 (0.53–1.21) | 0.00 |
| Tiger flathead | Tier_1a | failed (EM input; see below) | | | | | |
| | Tier_DD | −0.70 | −0.20 | 0.51 | 479 (316–612) | 0.74 (0.53–1.12) | 0.00 |

Findings:

- **Where Tier_1a works** (Morwong, Bight redfish, Deepwater flathead, School whiting), it estimates depletion more accurately than Tier_DD: median |RE| 0.13–0.25 against 0.17–0.64. It also takes 2–5 times more catch.
  - Tier_DD's pessimism leaves these stocks well above target at the end (0.52–0.92 against 0.34–0.54 under Tier_1a).
  - Its optimism for Bight redfish lowers the stock to 0.28 (5 % of simulations below 0.2).
- **Deepwater flathead and Pink ling:** Tier_DD is as accurate as Tier_1a or better (median |RE| 0.17 against 0.20, and 0.16 against 0.30). Pink ling's Tier_1a is biased high (+0.24 to +0.31).
- **Mirror dory:** both methods are biased high. Tier_1a's larger catches give P(end < 0.2) = 0.20.
- **Blue grenadier and Silver warehou: Tier_1a fails as an EM in this set-up.**
  - The SS fit at the first assessment has an unbounded scale. In simulation 1, SS SSB in the first model year was 4.9e8 t for Blue grenadier (OM 3.6e4 t), and 3.35e5 t for Silver warehou (OM 2.3e4 t; SS depletion 0.88 against OM 0.56 in 2025).
  - The first RBC was about 58,600 t for Blue grenadier and about 22,000 t for Silver warehou, against recent catches of about 12,600 t and 150–400 t.
  - The OM stock collapsed in every Blue grenadier simulation and in 95 % of the Silver warehou simulations.
  - This needs checking against the EM files (`Inputs CSIRO/Blue.grenadier.EM`, `Inputs Buffer/Silver.warehou.EM`: priors and bounds on R0, `SS_est_opt EstOnly` from the original par file, index set-up) before Tier_1a is used as the benchmark for these two stocks. Tier_DD is stable for both.
- **Tiger flathead Tier_1a fails before the first assessment.** SS stops with "Fatal Error! AFIX2 (Age post-settlement for L2, aka Amax) must be <= nages, entered value = 36". The EM data file has 20 ages (`#_Nages`), but the growth set-up (`#Growth:min/max age 3 36` in `Inputs CSIROM/Tiger.flathead.OM`, carried into the EM control file) puts L2 at age 36. This is an input inconsistency; both bundled SS executables come from the 3.30.24 era, so it should fail on Windows too. Tier_DD uses the OM growth directly and is not affected.
- **Run time:** Tier_1a took 8–152 minutes per stock (Blue grenadier slowest), against 6–20 minutes for Tier_DD.
- **Code note:** `R Inserts/Assessment.R` calls `file.remove("ss3par.par", showWarnings = F)` (and the same for `ss3.b01`). `file.remove()` has no `showWarnings` argument, so `FALSE` is taken as a second file name, which gives a warning at every SS run. Harmless, but noisy.

## 6. Reproducing

```bash
bash setup_linux.sh
```

```bash
source "$HOME/ratpack-env/activate.sh"
```

```bash
Rscript "MISC HCR/make_DD_inputs.R"
```

```bash
Rscript RunStreams/RunDDStock.R Tiger.flathead
```
