---
title: "Delay-difference EM (Tier_DD) in ratpackR: cloud tests, multistock runs and comparison with Tier_1a"
subtitle: "Summary of the work of 3–5 November 2026"
date: "10 November 2026"
---

# 1. Purpose and scope

This document summarises a series of cloud-based tests of the Fournier and Doonan (1987) length-based, generalised delay-difference model as an estimation method (EM) in ratpackR, André Punt's management strategy evaluation (MSE) framework (see Punt et al. 2016 for MSE practice). The method is `Ass$Type == "Tier_DD"` in `R Inserts/DelayDiff.R`. The work covered:

- confirming that the Morwong Tier_DD test gives the same results on a Linux cloud instance as on Windows;
- extending the test to the other single-stock SESSF operating models (OMs);
- fixing the robustness problems that came up;
- running 20 simulations per stock;
- comparing Tier_DD with the Stock Synthesis-based Tier_1a EM (Methot and Wetzel 2013) on the same OMs.

All of the work is on the branch `claude/elegant-feynman-9zx3v3` of the public fork `paulburch/ratpackR`, which is based on `paul/delaydiff-em`. No confidential or AFMA data were used; all inputs are those already in the repository.

**Links to results (GitHub)**

| What | Link |
|---|---|
| Branch | <https://github.com/paulburch/ratpackR/tree/claude/elegant-feynman-9zx3v3> |
| Detailed test report | [docs/delaydiff_multistock_tests.md](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/delaydiff_multistock_tests.md) |
| Tier_DD status and remaining work | [docs/delaydiff_em.md](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/delaydiff_em.md) |
| Linux set-up | [docs/cloud_setup.md](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/cloud_setup.md) |
| Single-simulation results (CSV) | [tier_dd_multistock_2026-11-04.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier_dd_multistock_2026-11-04.csv) |
| Tier_DD, 20 simulations: summary | [tier_dd_20sims_summary.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier_dd_20sims_summary.csv) |
| Tier_DD, 20 simulations: by simulation | [tier_dd_20sims_by_sim.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier_dd_20sims_by_sim.csv) |
| Tier_1a, 20 simulations: summary | [tier1a_20sims_summary.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier1a_20sims_summary.csv) |
| Tier_1a, 20 simulations: by simulation | [tier1a_20sims_by_sim.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier1a_20sims_by_sim.csv) |
| Tier_DD against Tier_1a | [tier_dd_vs_tier1a_20sims.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier_dd_vs_tier1a_20sims.csv) |

The raw ratpackR output files (`Results/`, `Temp/`) were written in a temporary cloud container and are not in the repository (they are git-ignored). The CSVs above hold all the numbers quoted here.

# 2. Requests (prompts) and what was done

| # | Request (paraphrased or quoted) | Outcome |
|---|---|---|
| 1 | Run the Tier_DD Morwong test (`RunStreams/RunDD.R`) on the cloud instance, plus the two standalone scripts in `MISC HCR/`, and report pass/fail, run times, RBC/TAC vectors, the 2020 depletion estimate and any differences from the Windows run of 3 Nov 2026. Do not commit. | All steps passed; results match Windows (§4.1). |
| 2 | "Run tests using the other species, write a summary report of the test and issues and push to github." | Inputs generated for 9 more stocks. In the first round 7 ran and 2 failed. Report pushed (§4.2). |
| 3 | "Can you let me run this on my phone?" | Explained: the Claude app on a phone can drive the cloud session, but R cannot run on the phone itself. |
| 4 | "Write key results to github after each analysis. Do you need me to provide more storage?" | Results are pushed after each analysis. No extra storage was needed (about 3 GB used of a 28 GB allowance). |
| 5 | "Yes apply the fixes and rerun both" (Blue grenadier, Orange roughy) | Both fixed and completed. A regression check was run on the other stocks (§5). |
| 6 | "Don't test on roughy" | Orange roughy east was removed from the tests. The guard for stocks without length data was kept. |
| 7 | "Run 20 simulations per stock" | 9 stocks × 20 simulations, 720 Tier_DD fits, no errors (§4.3). |
| 8 | "Compare with Tier_1a on the same OMs"; "run Tier_1a with 20 simulations too"; "push results to github when done" | 8 of 9 stocks completed; Tiger flathead failed on an input error (§4.4). |
| 9 | "Summarise all of this information, prompts, results etc into an md to html document. Include a link to the results." | This document. |

# 3. Methods

## 3.1 Computing environment

- Claude Code cloud container: Ubuntu 24.04, 4 cores, 16 GB RAM.
- R 4.5.3 (conda-forge, installed with micromamba), r4ss 1.56.0, RTMB 2.0, Rcpp 1.1.2 and RcppArmadillo 15.6.2.1. Set up with `bash setup_linux.sh`, which took 3 min 14 s (`docs/cloud_setup.md`).
- Stock Synthesis: `CodeBase/ss3_linux` (3.30.24 era), used only for Tier_1a.

## 3.2 The Tier_DD estimation model

The EM is the generalised, length-based delay-difference model of Fournier and Doonan (1987). It extends the delay-difference models of Deriso (1980) and Schnute (1985).

- **Population structure.** There are two groups: an unfished group 1 and a fished, mature group 2. Recruits enter at age `kage` with mean length `Tauk`, and growth is von Bertalanffy.
- **Recruitment.** The stock–recruitment relationship is Deriso–Schnute (Beverton–Holt here), with `beta` playing the role of steepness.
- **Fishery.** There is one aggregated fishery. Effort is catch divided by one CPUE index.
- **Length data.** One fleet's catch length compositions enter as their mean and central moments 2–4, with Sheppard's corrections for binning. The moments have Kendall–Stuart sampling variances.
- **Fitting.** RTMB is used in two phases (effort deviations first), started from three B0 scales.
- **Placeholder HCR.** This is a linear rule on fished-group depletion between `Dlim` = 0.2 and `Dtarg` = 0.48, applied to a target harvest fraction `Htarg` = 0.1. It has not yet been agreed (`docs/delaydiff_em.md`).

## 3.3 Inputs for the other stocks

`MISC HCR/make_DD_inputs.R` builds `Inputs DD/` for the stocks below:

- from `Inputs CSIRO/`: Bight redfish, Blue grenadier, Deepwater flathead, Mirror dory, Pink ling;
- from `Inputs CSIROM/`: Tiger flathead, School whiting;
- from `Inputs Buffer/`: Silver warehou.

Morwong uses the existing hand-set file. Redfish was not tested because `Inputs CSIRO/` has no `Redfish.OM`. Orange roughy east was excluded at Paul's request: it has no length data.

The OMs and their saved objects are copied unchanged. In each EM, only `Ass_Basic:Type` is switched to `Tier_DD`, and a `#Tier_DD:` block is added with priors derived from the OM biology (females):

- `kage` = growth A_min; `Tauk` = von Bertalanffy length at `kage` (SD 7 %);
- `Rho` = exp(−k) (SD 0.05); `Surv` = exp(−M) (SD 0.03);
- L∞ from L(A_min), L(A_max) and k; `Sigtau` = CV × mid length;
- `beta` = (1 − 0.2/h)/0.8, fixed; `Entry` = 0.4 (SD 0.15).

Applied to Morwong, this recipe reproduces the hand-set values. For each stock, the CPUE index and length fleet are those with future data and the most past observations.

## 3.4 Simulation design

| Setting | Value |
|---|---|
| Simulations | 1 (initial tests); 20 (§4.3–4.4) |
| Projection years | 10 |
| Assessment frequency | every 3 years (4 assessments) |
| Seeds | ratpackR default (`TheSeeds <- 1234`), so simulation 1 is the same in every run |
| `Estimation.test` | 99 (real data generation and estimation) |
| Parallelism | 4 stocks at a time, one R process each |

**Performance measures**

- **Relative error (RE)** = (EM − OM)/OM in depletion at the last data year of each assessment.
  - Tier_DD: fished-group biomass relative to year 1, against OM SSB relative to the first model year.
  - Tier_1a: SS SSB/SSB0, against the OM's `Total_Depletion` (SSB/SSB0).
- **Mean annual catch** over the 10 projection years.
- **OM end depletion**: OM SSB/SSB0 in the last projection year, the same measure for both methods.

# 4. Results

## 4.1 Morwong on the cloud instance (single simulation)

| Check | Result |
|---|---|
| `setup_linux.sh` | Pass (exit 0); no step blocked by the network policy |
| `RunDD.R` exit code | 0 (58 s; Windows about 1 min) |
| Tier_DD fits | 4 (2020, 2023, 2026, 2029) |
| Log ends with "done projecting" | Yes |
| `Results/Morwong.DD/` | Present (13 files) |
| Max-gradient warnings | None |
| RBC/TAC vectors | All 0 (as expected) |
| Estimated depletion, 2020 | 0.0193 (later assessments 0.025, 0.033, 0.042) |
| `fournier_doonan_delaydiff_RTMB.R` | Pass. Recursion errors 2e-10 to 6e-9 against the age-structured truth |
| `test_Run_DelayDiff.R` | Pass. Final depletion 0.576 and 0.646 against true 0.334 and 0.276 |
| Repeat run | Byte-identical estimates file |

## 4.2 Other stocks, single simulation

Eight stocks completed at the first attempt or after the input fix for the saved objects (§5). Blue grenadier needed the code fix in §5. The single-simulation results are in [tier_dd_multistock_2026-11-04.csv](https://github.com/paulburch/ratpackR/blob/claude/elegant-feynman-9zx3v3/docs/results/tier_dd_multistock_2026-11-04.csv), and the detailed tables are in §3 of the test report. A single realisation turned out to be a poor guide to bias: Pink ling looked strongly optimistic in simulation 1 but is unbiased over 20 simulations (§4.3).

## 4.3 Tier_DD, 20 simulations per stock

All 9 stocks completed all 20 simulations: 720 fits, with no errors and 24 (3 %) "max gradient > 0.01" messages. Each stock took 6–20 minutes. The ranges in brackets are 10th–90th percentiles.

| Stock | Median RE, A1 | Median RE, A4 | Median \|RE\| | EM depletion, A4 | OM depletion, A4 | Mean annual catch (t) |
|---|---|---|---|---|---|---|
| Morwong | −0.60 | −0.60 | 0.64 | 0.05 (0.04–0.10) | 0.15 (0.10–0.19) | 0 |
| Bight redfish | +0.36 | +0.43 | 0.48 | 0.43 (0.29–0.62) | 0.28 (0.22–0.60) | 1186 |
| Blue grenadier | −0.13 | −0.28 | 0.28 | 0.59 (0.43–0.75) | 0.82 (0.60–0.97) | 1899 |
| Deepwater flathead | −0.28 | +0.01 | 0.17 | 0.64 (0.38–0.87) | 0.64 (0.46–0.81) | 315 |
| Mirror dory | +0.12 | +0.19 | 0.15 | 0.97 (0.74–1.18) | 0.77 (0.63–1.06) | 264 |
| Pink ling | −0.01 | −0.03 | 0.16 | 0.59 (0.40–0.82) | 0.62 (0.53–0.72) | 220 |
| Tiger flathead | −0.70 | −0.20 | 0.51 | 0.54 (0.45–0.78) | 0.75 (0.53–1.12) | 479 |
| School whiting | −0.47 | −0.37 | 0.43 | 0.56 (0.33–0.90) | 0.88 (0.64–1.26) | 399 |
| Silver warehou | −0.09 | +0.05 | 0.14 | 0.83 (0.63–1.16) | 0.75 (0.52–1.09) | 754 |

- **Close to unbiased:** Deepwater flathead, Pink ling and Silver warehou (median RE within ±0.1 by the fourth assessment).
- **Pessimistic:** Morwong, School whiting, Blue grenadier, and Tiger flathead, which improves as data accumulate.
- **Optimistic:** Bight redfish (`kage` = 8) and, mildly, Mirror dory.

## 4.4 Tier_DD against Tier_1a, 20 simulations

Tier_1a completed for 8 stocks in 8–152 minutes per stock; Tiger flathead failed before its first assessment (§5). Note the different HCRs:

- Tier_1a uses the SESSF Tier 1 rule in the EM files (F_48 and B_48 targets, inflection 0.35, F = 0 at 0.20);
- Tier_DD uses the placeholder rule.

So the catch and outcome columns compare EM + HCR combinations, not the EMs alone.

| Stock | Method | Median RE A1 | Median RE A4 | Median \|RE\| | Mean catch (t) | OM end depletion | P(end < 0.2) |
|---|---|---|---|---|---|---|---|
| Morwong | Tier_1a | +0.15 | +0.03 | 0.13 | 183 | 0.34 | 0.05 |
| | Tier_DD | −0.60 | −0.60 | 0.64 | 0 | 0.52 | 0.00 |
| Bight redfish | Tier_1a | +0.07 | −0.03 | 0.13 | 607 | 0.54 | 0.00 |
| | Tier_DD | +0.36 | +0.43 | 0.48 | 1186 | 0.28 | 0.05 |
| Blue grenadier | Tier_1a | +2.36 | collapsed | — | 10760 | 0.00 | 1.00 |
| | Tier_DD | −0.13 | −0.28 | 0.28 | 1899 | 0.78 | 0.00 |
| Deepwater flathead | Tier_1a | +0.15 | +0.01 | 0.20 | 1030 | 0.44 | 0.05 |
| | Tier_DD | −0.28 | +0.01 | 0.17 | 315 | 0.65 | 0.00 |
| Mirror dory | Tier_1a | +0.03 | +0.29 | 0.25 | 1820 | 0.32 | 0.20 |
| | Tier_DD | +0.12 | +0.19 | 0.15 | 264 | 0.81 | 0.00 |
| Pink ling | Tier_1a | +0.24 | +0.31 | 0.30 | 668 | 0.42 | 0.00 |
| | Tier_DD | −0.01 | −0.03 | 0.16 | 220 | 0.63 | 0.00 |
| School whiting | Tier_1a | +0.14 | −0.09 | 0.25 | 2656 | 0.53 | 0.10 |
| | Tier_DD | −0.47 | −0.37 | 0.43 | 399 | 0.92 | 0.00 |
| Silver warehou | Tier_1a | +0.53 | collapsed | 0.96 | 2738 | 0.02 | 0.95 |
| | Tier_DD | −0.09 | +0.05 | 0.14 | 754 | 0.80 | 0.00 |
| Tiger flathead | Tier_1a | failed | | | | | |
| | Tier_DD | −0.70 | −0.20 | 0.51 | 479 | 0.74 | 0.00 |

**Main findings**

1. **Tier_1a is more accurate** for Morwong, Bight redfish and School whiting (median |RE| 0.13–0.25 against 0.43–0.64).
   - For Morwong and School whiting, Tier_DD's pessimism means much lower catches (0 and 399 t against 183 and 2656 t) and stocks well above target.
   - For Bight redfish, Tier_DD's optimism means about twice the catch (1186 t against 607 t) and a lower end depletion (0.28 against 0.54).
2. **Tier_DD is as accurate as Tier_1a, or better,** for Deepwater flathead (0.17 against 0.20), Mirror dory (0.15 against 0.25) and Pink ling (0.16 against 0.30). In each case it takes less catch and leaves the stock higher.
3. **Tier_1a collapses Blue grenadier and Silver warehou in this set-up.**
   - At the first assessment the SS fit has an unbounded scale: SSB in the first model year was 4.9e8 t against an OM 3.6e4 t (Blue grenadier), and 3.35e5 t against 2.3e4 t (Silver warehou).
   - The resulting RBCs (about 58,600 t and 22,000 t) collapsed the OM stock in 100 % and 95 % of simulations.
   - Tier_DD was stable for both stocks.
4. **Tier_DD is biased in a stock-specific way.** Its bias is probably linked to the generic priors (`Entry`, `kage`), to the structural mismatch with the OM (knife-edge groups, one aggregated fishery) and to the different quantities being compared (fished-group biomass against SSB).

# 5. Issues found and how they were handled

| # | Issue | Handling |
|---|---|---|
| 1 | My first driver passed `--args` as the stock name (`Rscript -e … --args`) | Fixed by using a wrapper script. Not a repository issue. |
| 2 | `SetSpec` needs `<Stock>.OM.SAV`; `Inputs CSIROM/` names these `.Sav`, which does not match on Linux | The generator copies them as `.SAV`. A permanent fix is to rename the files in `Inputs CSIROM/` (`RunCSIROM.R` would also fail on Linux). |
| 3 | Blue grenadier: a one-fish, one-bin length comp gives a negative variance after Sheppard's correction, so the likelihood is NaN and all fits fail | **Fixed** in `Run_DelayDiff`: comps with fewer than `MinBins` (3) occupied bins, a stated sample size below `MinNsamp` (default 0, off) or a non-positive corrected variance are skipped. 7 of the other 8 stocks gave byte-identical results; School whiting changed by at most 0.003 in depletion. |
| 4 | Orange roughy east has no length data, so `LD[,1]` failed | Guard added (fit to catch and effort only). Stock excluded from the tests at Paul's request. |
| 5 | Morwong's OM `Total_Depletion` (0.16 in 2020) is not SSB/SSB(1915) (0.05), because the OM starts above SSB0 | Documented. The choice of reference matters for comparing the EMs (remaining-work item 2 in `docs/delaydiff_em.md`). |
| 6 | Recurring warnings in André's code: `Totals + Outputs` length recycling in `WriteOut.R`; "NAs introduced by coercion" in `SetSpec`; `file.remove(..., showWarnings = F)` in `Assessment.R` | Reported, not changed. The `WriteOut.R` recycling may affect summary totals and is worth checking with André. |
| 7 | Tiger flathead Tier_1a: SS stops with "AFIX2 … must be <= nages, entered value = 36" (the EM has 20 ages) | Input inconsistency in the CSIROM files; it should fail on Windows too. Reported, not changed. |
| 8 | Blue grenadier and Silver warehou Tier_1a: unbounded SS scale | Reported. The R0 bounds or priors, the `EstOnly` start and the index set-up in the EM files need checking. |
| 9 | Background jobs are limited to 2 hours in the cloud session | The long runs were moved to a detached scheduler. |

# 6. Code and file changes on the branch

| File | Change |
|---|---|
| `MISC HCR/make_DD_inputs.R` | New: builds the Tier_DD inputs from the OM biology |
| `Inputs DD/` | Inputs for 8 more stocks (OM, EM, saved objects, general files) |
| `RunStreams/RunDDStock.R` | New: runs one stock; `RATPACK_DD_INPUTS` and `RATPACK_DD_TAG` select the input folder and tag the results |
| `R Inserts/DelayDiff.R` | Skips degenerate length comps; handles stocks with no length data |
| `R Inserts/ReadIn.R` | New `#Tier_DD:` options `MinNsamp` (0) and `MinBins` (3) |
| `docs/delaydiff_multistock_tests.md`, `docs/delaydiff_em.md`, `docs/results/*.csv` | Report, option documentation and results |

No changes were pushed to `upstream` or to `paul/delaydiff-em`.

# 7. Suggested next steps

1. Decide on the Tier_DD HCR and on which biomass quantity it, and the performance measures, should use.
2. Check the Tier_1a EM set-up for Blue grenadier and Silver warehou before using Tier_1a as a benchmark for them, and correct the Tiger flathead growth ages.
3. Explore the sensitivity of Tier_DD's bias to `Entry`, `kage`, `Sigtau` and the choice of CPUE and length fleets, for Bight redfish, Morwong, School whiting and Tiger flathead.
4. Add Tier_4a to the comparison, and run more simulations (for example 100) for the final performance statistics.
5. Rename the `Inputs CSIROM/*.Sav` files, and raise the `WriteOut.R` warnings with André.

# 8. Reproducing

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

For 20 simulations, copy `Inputs DD/` to a folder with `#Number_of_simulations 20` in the general files, then run:

```bash
RATPACK_DD_INPUTS="Temp/InputsDD20/" RATPACK_DD_TAG=20 Rscript RunStreams/RunDDStock.R Tiger.flathead
```

For Tier_1a, also switch `Ass_Basic:Type` to `Tier_1a` in the EM copies.

# References

Deriso, R.B. (1980). Harvesting strategies and parameter estimation for an age-structured model. *Canadian Journal of Fisheries and Aquatic Sciences* 37: 268–282.

Fournier, D.A. and Doonan, I.J. (1987). A length-based stock assessment method utilizing a generalized delay-difference model. *Canadian Journal of Fisheries and Aquatic Sciences* 44: 422–437.

Methot, R.D. and Wetzel, C.R. (2013). Stock synthesis: a biological and statistical framework for fish stock assessment and fishery management. *Fisheries Research* 142: 86–99.

Punt, A.E., Butterworth, D.S., de Moor, C.L., De Oliveira, J.A.A. and Haddon, M. (2016). Management strategy evaluation: best practices. *Fish and Fisheries* 17: 303–334.

Schnute, J. (1985). A general theory for analysis of catch and effort data. *Canadian Journal of Fisheries and Aquatic Sciences* 42: 414–429.
