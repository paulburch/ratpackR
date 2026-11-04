# Delay-difference EM (Tier_DD): status and remaining work

Branch `paul/delaydiff-em` on the fork (paulburch/ratpackR). Last updated 3 Nov 2026.

The Fournier & Doonan (1987) generalized, length-based delay-difference model (Can. J. Fish. Aquat. Sci. 44: 422-437) is wired into ratpackR as an estimation method, `Ass$Type = "Tier_DD"`. Each assessment year it fits the model to catch, effort (catch / CPUE) and the moments of a catch length composition. It then projects the fitted model under a harvest control rule to give the 50-year RBC vector that `Run_Assessment` returns.

## Files

| File | What it is |
|---|---|
| `R Inserts/DelayDiff.R` | The model and the method: `f_dd(parms, data)` (RTMB objective), `dd_advance` (moment update), `DD_comp_moments`, `DD_project` (projection under an HCR), `Run_DelayDiff` (the ratpackR method). Sourced by `RatpackR.R`. |
| `R Inserts/Assessment.R` | One dispatch line in `Run_Assessment` for `Tier_DD`. |
| `R Inserts/ReadIn.R` | Reads the `#Tier_DD:` options from the `.EM` file into `Ass$DD`. |
| `MISC HCR/fournier_doonan_delaydiff_RTMB.R` | The paper's simulation example: checks `f_dd` against a full age-structured model, then fits it. |
| `MISC HCR/fournier_doonan_sim.R` | The age-structured simulator (`sim_fd`). It can also return binned length comps. |
| `MISC HCR/test_Run_DelayDiff.R` | End-to-end test of `Run_DelayDiff` on simulated data packed into a mock `Stock` object, with gaps in the index and length data. |
| `MISC HCR/test_DelayDiff_seeds.R` | Estimation performance over 10 simulated data sets for 4 settings. |
| `Inputs DD/` | Morwong (1 area, 1 sex), copied from `Inputs CSIRO/`, with the EM set to `Tier_DD`, 1 simulation, 10 projection years and an assessment every 3 years. |
| `RunStreams/RunDD.R` | Runs `Inputs DD/` from the repository root (`Path <- getwd()`). An optional command-line argument sets `Estimation.test`. |

All scripts are run from the repository root.

## Model as implemented

- Two groups. Group 1 is not fished; fish move to group 2 (fished and mature) with annual probability `Entry`. Recruits enter group 1 at age `kage` with mean length `Tauk`, and growth follows von Bertalanffy (`rho = exp(-k)`, `Linf`). Within-age SD of length is fixed (`Sigtau`), and weight is `bwl * L^3`. `bwl` is refitted from the EM weight-length with b = 3 over the length bins, because the model needs the cubic exponent.
- The year-1 state is unfished equilibrium. Recruitment follows the Deriso–Schnute SR (`gamma_sr`: 1 = Beverton–Holt, 0 = Ricker) with productivity tied to the unfished state (`SRvirgin = 1`), so `beta` plays the role of steepness. For BH, `beta = (1 - 0.2/h)/0.8`.
- There is a single aggregated fishery. Effort is catch / CPUE for one index. In years with no index, effort is a free parameter set by the catch (no effort penalty). Years with zero catch are left out of the catch likelihood, and their effort is fixed near 0.
- Length data are one fleet/part comp per year, reduced to its mean and central moments 2–4 (Sheppard-corrected for equal bins). These are fitted with Kendall–Stuart sampling variances using the stated sample size (`LD[,7]`, the EFN, capped at `MaxNsamp`). Comps in zero-catch years are dropped, because ratpackR generates them from an almost empty catch.
- Missing observations are masked out of every likelihood term. Recruitment deviations are estimated from `RecDevLead` years before the first length comp onward.
- Fitting: phase 1 fits the effort deviations to the catches, then phase 2 fits all parameters. This runs from three B0 scales and keeps the best objective. Without phase 1 the Morwong fit went to a local optimum with B0 ≈ 2.6e11 t, where fishing has no effect.

## `.EM` options (`#Tier_DD:<name> value(s)`)

Two values are a prior mean and SD; an SD ≤ 0 means no prior. Options marked * have no default and must be given.

| Option | Default | Meaning |
|---|---|---|
| `Cpue_Area`, `Cpue_Index` | 1, 1 | CPUE index used to derive effort |
| `Len_Area`, `Len_Fleet`, `Len_Part` | 1, 1, 0 | length comps used (Part: 0 total, 1 discard, 2 retained) |
| `MaxNsamp` | 1000 | cap on the stated sample size |
| `MinNsamp`, `MinBins` | 0, 3 | skip comps with a smaller stated sample size or fewer occupied bins (and any comp whose Sheppard-corrected variance is ≤ 0) |
| `kage`* | | age at entry to group 1 |
| `Amax` | 100 | ages used for the unfished state |
| `gamma_sr`, `beta_init`, `EstBeta` | 1, 1, Yes | SR form, starting value / fixed value, estimate? |
| `sigmaC`, `sigmaE`, `sigmaR` | 0.05, 0.3, 0.6 | SDs: log catch, log effort, rec devs |
| `lamM` | 0 | SD multiplier for mean weight (0 = off; in ratpackR it comes from the same lengths) |
| `lamL` | 1 1 1 1 | SD multipliers for length moments 1–4 (0 = off) |
| `Rho`*, `Surv`*, `Entry`*, `Tauk`* | | priors (mean, SD) on exp(-k), exp(-M), entry probability, length at `kage` |
| `Linf_init`*, `EstLinf` | , Yes | Linf start / fixed value |
| `Sigtau`* | | within-age SD of length |
| `Q2`, `EstQ2` | 0 0.5, No | biomass-dependent catchability prior; estimate? |
| `Q1sd` | -1 | SD of a lognormal prior on Q1, centred on the start guess (off by default) |
| `MaxLen_g1`, `lamPen` | 0, 0 | soft upper bound on the group-1 mean length, and its weight |
| `B0_init_mult` | 10 | starting B0 = this × the largest catch (fits also start from ×1/3 and ×3) |
| `RecDevLead` | 0 | estimate recruitment deviations from this many years before the first comp |
| `lamRecSum` | 0 | weight of a sum-to-zero penalty on the recruitment deviations |
| `Dlim`, `Dtarg`, `Htarg`* | 0.2, 0.48, | placeholder HCR (below) |

`Inputs DD/Morwong.EM` holds a commented example set for Morwong (k 0.236 → `Rho` 0.79; M 0.15 → `Surv` 0.861; L at age 3 = 21.45; h 0.7 → `beta` 0.893).

## Tests and results (3 Nov 2026)

1. **Recursions:** at the true parameters, `f_dd` reproduces the age-structured simulator to about 1e-9 for catch, mean weight, length moments 1–4, biomass and recruitment. This is unchanged by the move into `R Inserts`.
2. **Wiring, simulated data with gaps:** `test_Run_DelayDiff.R` runs `Run_DelayDiff` at two assessment years and returns finite 50-year RBC vectors. Its seed (202) is a weakly informative draw: final depletion is estimated at 0.65 against a true 0.28. Over seeds 301–310, the median relative error in final depletion is +9% and the median absolute relative error 23% (`test_DelayDiff_seeds.R`). Turning on the mean-weight term, adding a Q1 prior or estimating recruitment deviations in all years changes this by only 1–3 percentage points.
3. **ratpackR run, Morwong (`RunStreams/RunDD.R`, R 4.4.1, `Estimation.test = 99`):** completes in about 1 minute, with assessments in 2020, 2023, 2026 and 2029.
   - The OM has Morwong heavily depleted: in 2020, SSB/SSB0 is 0.05 and fleet-1 selected biomass is 0.05 of its 1915 level.
   - The EM estimates fished-group depletion of 0.02–0.03 in 2020 and 0.13–0.19 in 1990 (true 0.36). So it is too pessimistic, but it ranks the stock correctly as below the limit.
   - With the placeholder HCR (`Dlim` 0.2), every TAC in the 10 projection years is 0.

## Remaining work

1. **HCR (decide with Paul).** `Run_DelayDiff` uses a placeholder: a linear rule on fished-group depletion (`Dlim` to `Dtarg`) times a target harvest fraction `Htarg`, run through `DD_project` so the 50-year RBC vector has feedback, as in Tier_4a. The options are:
   - keep a depletion-based rule, but decide which biomass it uses (the fished group here, not SSB);
   - F&D's own approach, the effort or harvest rate that gives maximum long-term yield from the fitted model;
   - an F_MSY or F_48 proxy from the fitted model, applied through `DD_project`.
2. **Compare like with like.** `Depl.estimates` stores fished-group biomass relative to year 1, and `SSB.estimates` stores group-2 biomass. ratpackR's performance measures compare these with OM SSB/SSB0. For Morwong the two are close (both 0.05 in 2020), but they won't be in general. Decide what to store before using the summary statistics.
3. **Structural mismatch with the OM.** The OM uses length-based logistic selectivity and retention by fleet, and its length-at-age SD grows with length (CV 0.10). The EM uses knife-edge groups, one aggregated fishery and a constant `Sigtau`. The Morwong bias in 1990 (0.13–0.19 against 0.36) probably comes mostly from this, and the MSE should measure it rather than tune it away. Worth testing whether `Entry` and `Sigtau` choices change it.
4. **Weak length information.** Morwong's fleet-1 retained comps have EFNs of 5–45, so the length moments carry little weight and scale comes mainly from catch and CPUE. Try `lamL` < 1 (upweighting) or larger `MaxNsamp` with real sample sizes, and consider fitting more than one fleet's comps.
5. **Optimiser.** nlminb usually reports "false convergence (8)" with max gradient about 1e-3 to 2e-2. The Morwong likelihood has more than one optimum (a refit from a Q1-prior solution reached objective 258.8, against 266.5 for the standard fit, with similar depletion). Consider more starts, a jitter, or checking the Hessian (`sdreport`) in the MSE loop.
6. **MSE test design.** Steps, roughly in order:
   - deterministic data (`Rscript RunStreams/RunDD.R 2`) to check the EM tracks the OM;
   - then stochastic replicates (`#Number_of_simulations`, `#Number_of_projection_years 25`, assessment frequency);
   - compare with Tier_1a and Tier_4a on the same OM, which needs a second EM copy with only `Ass_Basic:Type` changed;
   - then a stock that is less depleted than Morwong, so the HCR is exercised.
7. **Parallel version.** `R Inserts/Parallel/RatpackR.R` and `Assessment.R` don't have the Tier_DD source line or dispatch yet.
8. **Linux / cloud.** `linux-portability` is merged into this branch (correct file-name case, `RATPACK_ROOT` paths). To run on Linux, use `docs/cloud_setup.md`: `bash setup_linux.sh`, then `source "$HOME/ratpack-env/activate.sh"`, then `Rscript RunStreams/RunDD.R` from the repository root.
9. **Tidy-up for Paul.** `C:/_AI/Claude_code/Other_assessments/Fournier_Doonan_1987_delay_difference/` holds the original standalone script, which is now duplicated here.

## Environment notes

- `RunDD.R` was run with R 4.4.1 (`C:/Programs/R/R-4.4.1`, Rtools44; RTMB, Rcpp, RcppArmadillo and r4ss installed).
- The standalone tests were run with R 4.6.1. TMB and RTMB were reinstalled there on 3 Nov 2026, because the existing TMB binary failed to load.
- Outputs go to `Results/` and `Temp/`, which are not committed.
