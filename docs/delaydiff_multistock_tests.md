# Tier_DD (delay-difference EM) tests on ten SESSF stocks

Branch `claude/elegant-feynman-9zx3v3` (based on `paul/delaydiff-em` at d372de8). Run on 4 Nov 2026 in a
Claude Code cloud container: Ubuntu, R 4.5.3 (conda-forge), r4ss 1.56.0, RTMB 2.0, Rcpp 1.1.2,
RcppArmadillo 15.6.2.1, set up with `setup_linux.sh` (3 min 14 s). Key numbers are also in
[`docs/results/tier_dd_multistock_2026-11-04.csv`](results/tier_dd_multistock_2026-11-04.csv).

## 1. Summary

| Result | Stocks |
|---|---|
| Completed: 4 Tier_DD assessments, 10 projection years, exit 0 | Morwong, Bight redfish, Deepwater flathead, Mirror dory, Pink ling, Tiger flathead, School whiting, Silver warehou (8) |
| Failed at the first assessment | Blue grenadier (negative variance from a 1-fish length comp; §4.1), Orange roughy east (no length data; §4.2) |

- No code in `R Inserts/` was changed. The two failures are robustness issues in `Run_DelayDiff` (§4). The fixes are described, not committed.
- The Morwong cloud run matches the single-stock cloud run of 3 Nov exactly (the estimates file is byte-identical between repeat runs), and it matches the Windows result: all TACs 0; estimated depletion 0.019 in 2020.
- The EM depletion estimates are within about ±0.15 of the OM for Deepwater flathead, Mirror dory and Silver warehou (last three assessments). They are biased high for Bight redfish and Pink ling, and biased low for Morwong, Tiger flathead and School whiting (§3).

## 2. What was run

- **Inputs.** `MISC HCR/make_DD_inputs.R` builds `Inputs DD/<Stock>.{OM,EM,OM.SAV,EM.SAV}` and `General_<Stock>.OM` from `Inputs CSIRO/` (Bight redfish, Blue grenadier, Deepwater flathead, Mirror dory, Orange roughy east, Pink ling), `Inputs CSIROM/` (Tiger flathead, School whiting; single-stock general files) and `Inputs Buffer/` (Silver warehou). The OM is copied unchanged. The EM is switched to `Tier_DD` and gets a `#Tier_DD:` block. The general file is set to 1 simulation, 10 projection years and an assessment every 3 years, as for Morwong. Redfish was not tested, because `Inputs CSIRO/` has no `Redfish.OM`.
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
| Orange roughy east | 3 | none | 1 | 0.942 | 0.962 | 8.66 | 39.1 | 1.7 |
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
| Deepwater flathead | 56 s | 2022, 25, 28, 31 | 0.275, 0.425, 0.560, 0.694 | 0.401, 0.482, 0.572, 0.681 |
| Mirror dory | 50 s | 2025, 28, 31, 34 | 1.046, 1.443, 0.978, 0.803 | 0.915, 1.755, 1.038, 0.791 |
| Pink ling | 73 s | 2025, 28, 31, 34 | 0.370, 0.717, 1.161, 1.044 | 0.375, 0.446, 0.484, 0.528 |
| Tiger flathead | 81 s | 2025, 28, 31, 34 | 0.116, 0.209, 0.394, 0.550 | 0.367, 0.495, 0.723, 0.759 |
| School whiting | 39 s | 2025, 28, 31, 34 | 0.292, 0.320, 0.515, 0.698 | 0.464, 0.646, 0.788, 1.290 |
| Silver warehou | 104 s | 2025, 28, 31, 34 | 0.170, 0.654, 0.735, 0.681 | 0.563, 0.671, 0.736, 0.999 |

Total TAC (t, summed over fleets) in each of the 10 projection years, under the placeholder HCR
(`Dlim` 0.2, `Dtarg` 0.48, `Htarg` 0.1):

| Stock | Years 1–10 |
|---|---|
| Morwong | 0 0 0 0 0 0 0 0 0 0 |
| Bight redfish | 1357 1237 1130 1398 1275 1166 999 917 786 1065 |
| Deepwater flathead | 33 127 199 182 204 225 235 252 265 594 |
| Mirror dory | 282 294 285 299 262 234 237 224 216 217 |
| Pink ling | 87 148 198 319 316 308 503 471 431 471 |
| Tiger flathead | 0 0 79 173 281 449 671 807 934 942 |
| School whiting | 96 264 315 181 287 333 331 373 403 405 |
| Silver warehou | 32 50 58 509 469 421 544 502 446 442 |

Notes:

- This is one simulation per stock, so these are single realisations, not performance statistics.
- With 1 simulation and an assessment every 3 years, the TAC is held between assessments. The changes within those 3-year blocks come from how ratpackR applies the TAC across fleets, not from the EM.
- Optimiser: one "Tier_DD: max gradient 0.0139, false convergence (8)" message (Silver warehou). All other fits had max gradient < 0.01.
- The HCR is exercised for the first time: Tiger flathead's first assessment (0.116 < `Dlim`) gives 0 TAC, and the others give positive TACs.

## 4. Issues found

1. **Blue grenadier: all fits fail (NaN).** One retained length comp of fleet 4 contains a single fish (n = 1, one non-empty bin). With 2-cm bins, Sheppard's correction makes its variance negative (0.0 − 2²/12 = −0.333). Then `sqrt(L2o/n)` in the length-moment likelihood (`R Inserts/DelayDiff.R`, `f_dd`) is NaN, so every start fails and `Run_DelayDiff` stops with "all fits failed". Suggested fix in `Run_DelayDiff`: skip comps whose corrected variance is ≤ 0, or whose sample has fewer than a minimum number of fish (for example n < 10) or occupies fewer than 3 bins. A `MinNsamp` option would make the threshold explicit.
2. **Orange roughy east: `Error in LD[, 1]: incorrect number of dimensions`.** The stock has no length data (age data only), so `Data$LengthData.Used` is not a matrix. Suggested fix: `if (is.null(dim(LD))) rows <- integer(0)`. Even then, the EM would be fitted to catch and an egg-survey index only. Orange roughy probably needs an age-based option, or should be left out of Tier_DD.
3. **`Inputs CSIROM/*.Sav` is not found on Linux.** `SetSpec` (`R Inserts/ReadIn.R`) loads `<Stock>.OM.SAV`, but `Inputs CSIROM/` spells the files `.OM.Sav`. `RunCSIROM.R` would fail on Linux for the same reason. The generator copies them as `.SAV`. A permanent fix is to rename the files in `Inputs CSIROM/` (a rename only, so it's safe for upstream merges), and it belongs with the `linux-portability` changes.
4. **The OM's `Total_Depletion` for Morwong is not SSB/SSB(1915).** In `ProjectAll`, Morwong's `Total_Depletion` in 2020 is 15.98 %, but SSB(2020)/SSB(1915) is 0.050 (the 0.05 quoted in `docs/delaydiff_em.md`). The OM starts above SSB0 (`#Early_R0Mult 1.17`), so `Total_Depletion` uses a different reference than year 1. For the other stocks the two are equal. This matters for remaining-work item 2 in `docs/delaydiff_em.md` (which quantity to compare the EM with).
5. **Recurring warnings from the main code, not Tier_DD.** These occur for every stock:
   - `Totals + Outputs` "longer object length is not a multiple…" (`R Inserts/WriteOut.R` lines 294, 317, 479; 54–268 times per run);
   - `SetSpec` "NAs introduced by coercion" (6–27 times, while reading the inputs);
   - one `rbind(Stock[[Istock]]$Data$LengthData, Vec1)` column-mismatch warning.

   They do not stop the runs, but the `WriteOut.R` recycling may make some summary totals wrong. Worth checking with André.
6. **EM bias pattern** (one realisation, so this is indicative only).
   - Biased low (more pessimistic than the OM): Morwong, Tiger flathead, School whiting, Silver warehou in its first assessment.
   - Biased high (more optimistic): Bight redfish, and Pink ling after its first assessment (EM > 1 by 2031).
   - Possible causes: generic priors (`Entry` 0.4 for every stock, `kage` = growth A_min, which is 8 for Bight redfish and 1 for four stocks), effort derived from one CPUE series, and comps from one fleet. Pink ling and Mirror dory are 4-area OMs whose catches are summed into one fishery.

## 5. Suggested next steps

1. Fix §4.1 and §4.2 in `Run_DelayDiff`, then re-run Blue grenadier and Orange roughy.
2. Run several simulations per stock (for example 20) to separate bias from noise, and compare with Tier_1a and Tier_4a on the same OMs.
3. Check the sensitivity to `Entry`, `kage` and the choice of CPUE and length fleets for the biased stocks (Bight redfish, Pink ling, Tiger flathead).
4. Rename the `Inputs CSIROM/*.Sav` files (§4.3).

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
