# ratpackR: bugs found, fixes applied and how they were tested

**For:** André Punt
**From:** Paul Burch
**Date:** 4 November 2026

## Where the code is

| What | Link |
|---|---|
| Your repository (upstream, `main`, reviewed at commit `e57b8ca`) | https://github.com/puntae/ratpackR |
| My fork | https://github.com/paulburch/ratpackR |
| Branch with the fixes | https://github.com/paulburch/ratpackR/tree/bugfix-experiments (commit `824437b`) |
| Full bug review (45 items, line references, reproducible checks) | [`docs/bug_review.md`](https://github.com/paulburch/ratpackR/blob/bugfix-experiments/docs/bug_review.md) |
| Fix-by-fix log with test results | [`docs/bugfix/bugfix_log.md`](https://github.com/paulburch/ratpackR/blob/bugfix-experiments/docs/bugfix/bugfix_log.md) |
| Regression tests | [`tests/README.md`](https://github.com/paulburch/ratpackR/blob/bugfix-experiments/tests/README.md), `tests/run_all.sh` |
| Unfixed code with the same Linux set-up (for comparison) | branches `linux-portability` and `bug-review` |
| Every change on the branch compared with your `main` | https://github.com/puntae/ratpackR/compare/main...paulburch:ratpackR:bugfix-experiments |

Bug numbers below (#1–#45) are the ones used in `bug_review.md` and the fix log. Each fix
is **one commit** on `bugfix-experiments` whose message starts `Fix #n:` (or
`Fix suspected #n:`), so you can look at, take or drop any fix on its own. The **Commit**
column in the tables links to that commit on GitHub, which shows the diff. Each fix commit
also adds that fix's entry to `docs/bugfix/bugfix_log.md`, so the diff shows the log entry
as well as the code change. Most changed lines carry a `# FIX #n` comment.

## Summary

- I reviewed `RatpackR.R` and `R Inserts/` (`ReadIn.R`, `Assessment.R`, `DataGen.R`,
  `WriteOut.R`, `SaveFiles.R`, `Model.cpp`, `Utils.cpp`) and the parallel copies, at your
  commit `e57b8ca`. That gave **24 confirmed bugs** (#1–#24) and **21 further items**,
  mostly suspected (#25–#45).
- **38 items are fixed**: all 24 confirmed bugs, and 14 of the further items. Six items
  were left unchanged on purpose and one (#45) turned out to be an input problem, not a code
  bug.
- **No fix broke another part of the code.** Fixes were applied one at a time, in severity
  order, and after each one the reproducible checks and the smoke runs were repeated and
  every output file was compared with the previous step.
- **Most fixes do not change results for the current single-stock, single-area inputs**;
  they matter for multi-stock or multi-area runs, or for options the current inputs don't
  use (Tier 4a/4b/5, discard ages, closed areas, `CatchType` 3, and so on). Five fixes do
  change outputs of the standard runs, listed in the next section.
- **Several fixes involve a modelling choice I made in your place.** They are listed under
  "Decisions for you"; please check them before anything goes into your `main`.

## Fixes that change results of current runs

| # | Fix | Effect on the Silver warehou test runs | Commit |
|---|---|---|---|
| 1 | `FixedCosts` read from a 5th economic value that the `.OM` files don't have, so Cost and Profit were NA everywhere | Cost and Profit columns go from NA to numbers; nothing else changes | [`8196c26`](https://github.com/paulburch/ratpackR/commit/8196c26441f992cb52dfb9f26ca4d8c5450e7493) |
| 2 | `SetBuffer` overwrote the default buffer with the time buffer, so `#Buffer_specifications:Default` was never applied | The 2026 TAC is now 0.9 × the old value with `Inputs Buffer/` (6727 → 6054 t, no estimation; 2147 → 1933 t, with estimation). **Earlier buffer-study results did not include the 0.9 default.** RBCs are unchanged | [`d9ec2b5`](https://github.com/paulburch/ratpackR/commit/d9ec2b5198d0da631c12d0255bca2bca8169da77) |
| 19 | Typo `CatchDiscardl` in `WriteOut.R`, so per-area discards were always written as 0 | `ProjectFleetArea` discards now total 6792 t, matching `ProjectAll` | [`18a60f0`](https://github.com/paulburch/ratpackR/commit/18a60f0a229715f6fa849667eadd5c5f4963e900) |
| 21 | Discard deviations called `set.seed(Seed)`, restarting the seed chain, so later random streams repeated earlier ones (for example, age-sample seeds equalled the catastrophic-M draws) | Stochastic runs draw different random numbers; **they no longer reproduce older runs draw for draw**. Deterministic runs are unchanged | [`6de9974`](https://github.com/paulburch/ratpackR/commit/6de99740d496e29bbdf719ac5717181d0b3e069e) |
| 36 | Deterministic age and CAA observations were `Nsamp × Expected` without normalising (lengths were normalised) | With SS estimation, parameter estimates shift by at most 2e-5 (relative); RBC and TAC unchanged | [`5a785b6`](https://github.com/paulburch/ratpackR/commit/5a785b65aab54f5077ec47d387578d13d6cd5c54) |

Fix #3 does not change results but changes disk use: the SS clean-up block could never run
(`!Estimation.test %in% 99` after an early return for values below 99). Each assessment
folder now keeps 1.7 MB instead of 11 MB; a 100 × 25 run would otherwise fill about 27 GB.

## All fixes

Severity: **High** = wrong numbers or a crash with the current inputs or run streams;
**Medium** = wrong or crashing in documented options the current inputs don't use;
**Low** = output, warnings or robustness; **S** = suspected item from the further findings.

| # | Sev. | Where | Problem | Fix | Test evidence | Commit |
|---|---|---|---|---|---|---|
| 1 | High | `ReadIn.R` | `FixedCosts` NA, so Cost and Profit NA | 5th value optional, default 0 | Check B02/B02b; outputs above | [`8196c26`](https://github.com/paulburch/ratpackR/commit/8196c26441f992cb52dfb9f26ca4d8c5450e7493) |
| 2 | High | `RatpackR.R` `SetBuffer` | Default buffer never applied | `max(Min.Buffer, Buffer × T.Buffer)` | Check B01; TAC × 0.9 | [`d9ec2b5`](https://github.com/paulburch/ratpackR/commit/d9ec2b5198d0da631c12d0255bca2bca8169da77) |
| 3 | High | `Assessment.R` `Run_Tier1a` | SS clean-up never runs | Condition inverted to `Estimation.test %in% 99` | E99 run: folder 11 → 1.7 MB | [`b654632`](https://github.com/paulburch/ratpackR/commit/b65463211fca2d8f79c94fc811c6f5a6cb34632e) |
| 4 | High (multi-stock) | `Do.Project` | Allocation loop variable `Istocks`, body uses `Istock`: only the last stock re-allocated | Loop variable `Istock` | Check B09 | [`bc18adb`](https://github.com/paulburch/ratpackR/commit/bc18adbf3b66e245bd6f10e8b8039a55739708c2) |
| 5 | High (multi-stock) | `PGMSY` | Divides by zero recent catch of the primary stock (NaN crash, or Inf giving TAC 0) | Such a fleet is treated like an unlinked fleet (TAC carried over) | Check B14 | [`b986afb`](https://github.com/paulburch/ratpackR/commit/b986afb28868ddca7962964f9d0fdd0ef75ab18e) |
| 6 | Medium | `Do.Project` | `matrix(TACs[...], byrow=T)` mixes areas and fleets when `NassArea > 1` | No `byrow`; only the stock's own assessment areas | Synthetic test: 11, 22, 33 recovered | [`1940f9b`](https://github.com/paulburch/ratpackR/commit/1940f9b205229825a0f9ad30a53dd4808d8d41c8) |
| 7 | Medium | `SPR_ref` | Moved fish added to the source area; plus group not transposed; catch summed for the last area only | Destination area; `t(Amove)` as in `Get.Initial`; loop over areas | Checks B10a, B10c | [`9a0fd2e`](https://github.com/paulburch/ratpackR/commit/9a0fd2ec945ceaecd112efcb4faa769b9c5dd6fb) |
| 8 | Medium | `Get.Initial`, equilibrium catch, `SPR_ref` | Movement at age a−1, but `Project.One.Ahead` uses age a | All use `Move[,,Iage]` | Check B10b: the three routines now agree exactly | [`551957e`](https://github.com/paulburch/ratpackR/commit/551957e42a5e59dbd08999c0ded72bdc1a2cf58a) |
| 9 | Medium | `Assessment.R` `Write_ctl` | Positive steepness bias multiplier ignored | `h × bias` (negative still means fixed h) | Check B05 | [`9c3a24e`](https://github.com/paulburch/ratpackR/commit/9c3a24ed47b092e08a578b95c270dcc3e15d09af) |
| 10 | Medium | `ReadIn.R`, `Do.Project` | Early-R0 block end stored as `.end.yrs`, read as `_end_yrs` | One name | Check B04 | [`cc28dec`](https://github.com/paulburch/ratpackR/commit/cc28dec83cd36b54b2479e6b993012a8d078973d) |
| 11 | Medium | `ReadIn.R` | Catch bias: every fleet read fleet 1's row; last segment not filled to the end | Own row per fleet; compare with `Nhist+Nproj+1` | Checks B03a, B03b | [`894adaf`](https://github.com/paulburch/ratpackR/commit/894adafeebfb8c3e092a679657f6d1f6aea262f9) |
| 12 | Medium | `Run_Tier4b` | `Tier4b$Cpue_lim` partially matched `Cpue_limit_mult`; RBC could go negative | Compare with `Cpue.limit` | Rule checked separately; not run end to end (no Tier 4b input) | [`f20a4d4`](https://github.com/paulburch/ratpackR/commit/f20a4d47e79e13e2233f8c6264ec5de02fb9ecf0) |
| 13 | Medium | `DataGen.R` | `Stock[[Iarea,Istock]]` crashes with discard age data | `Stock[[Istock]]$...[Iarea,...]` | End to end: old code crashes, new code writes the discard ages | [`ef5761c`](https://github.com/paulburch/ratpackR/commit/ef5761c03c515d4a7e07d7a42ac2dfbc980299b6) |
| 14 | Medium | `Do.Project` | `TAC.management = "No"` (every Tier 5 run) uses undefined `TACsOrig` | TAC set to 0; F comes from `Ass$F.fix` | End to end: Tier 5 run crashed, now completes | [`4e19e71`](https://github.com/paulburch/ratpackR/commit/4e19e71e83cc15187ecf70b3198e168e1606c7c2) |
| 15 | Medium | `ReviewFsolver`, `ReadIn.R` | `CatchType` 3: 3-D `F.Selex.Inp` indexed with 2 subscripts; input F all zeros ("AEP FIX" commented out) | `F.Selex.Inp[,Ifleet,]`; F filled from `OM.obj$Fleet.F.data`, same F in every open area | End to end: reproduces input catches exactly for 1980–2022 (see notes) | [`590979a`](https://github.com/paulburch/ratpackR/commit/590979ada4e26cc8d6fd6093d71b0a6e2bfa12b0), [`5361e8c`](https://github.com/paulburch/ratpackR/commit/5361e8ca442ca666fa3a9bd281fa48c7d7917e09) |
| 16 | Medium | `Run_Tier4a` | `map=list(logr=...)` should be `logR` (crash with `EstR No`, `EstZ Yes`) | `logR` | End to end (P.cod): crashed, now completes | [`c83e219`](https://github.com/paulburch/ratpackR/commit/c83e2198dbeba615a2584000376b279b2683148e) |
| 17 | Medium | `R Inserts/Parallel/` | Old copy of the engine, incompatible with the current `ReadIn.R` | Replaced by a thin driver over the current engine, `DoRunParallel(GeneralFile, RunNo, n_cores)` (base `parallel`, Windows and Linux) | Serial vs parallel, 2 simulations, E99: all 11 output files identical | [`9222d48`](https://github.com/paulburch/ratpackR/commit/9222d48cc58c5e09d94781ebdfd48b743c2ba093) |
| 18 | Medium | `Project.One.Ahead` | Catch-fleet CPUE predictions multiply by age selectivity twice | Drop `SelexAge` (already in `SelRetWghtAge`) | No effect for current inputs (0/1 age selectivity) | [`5d5d2a5`](https://github.com/paulburch/ratpackR/commit/5d5d2a5bbcf7694d328be06c4a614d738855e892) |
| 19 | Low | `WriteOut.R` | `CatchDiscardl` typo; `$Full` worked only by partial matching | `CatchDiscard`, `$FullF` | Discards by area 0 → 6792 t | [`18a60f0`](https://github.com/paulburch/ratpackR/commit/18a60f0a229715f6fa849667eadd5c5f4963e900) |
| 20 | Low | `Write_ctl` `.par` writer | Descending rec-dev bias ramp mixed calendar and model years (≈ 1 instead of 1 → 0) | Calendar years throughout | Ramp now 1, 0.83, …, 0 | [`618333d`](https://github.com/paulburch/ratpackR/commit/618333d1117a3f11bc5c770f7d5a34d05c276e6d) |
| 21 | Low | `ReadIn.R` | Random streams re-used | `set.seed(NextSeed)` | Check B16 | [`6de9974`](https://github.com/paulburch/ratpackR/commit/6de99740d496e29bbdf719ac5717181d0b3e069e) |
| 22 | Low | `ReadIn.R` | `LengthData` seed row one column short | `7 + Nsex × Nlen` | Check B18; warning gone | [`84f068a`](https://github.com/paulburch/ratpackR/commit/84f068a9e3f4b43382fe6fd06a0d5389fb19e476) |
| 23 | Low | `Assessment.R` | `file.remove(..., showWarnings=F)` tries to delete a file called `FALSE` | Argument dropped (calls already guarded) | Warnings gone | [`9877517`](https://github.com/paulburch/ratpackR/commit/9877517cd0bb8afa9fc1cd42cc18eaa25e5bd59f) |
| 24 | Low | `WriteInsurance` | `Totals` has 35 values, each fleet block 41 | `rep(0, 41)` | 48 warnings per simulation gone | [`670ba9d`](https://github.com/paulburch/ratpackR/commit/670ba9db0387289ef9ddbe9b4fc7058edd8d0eeb) |
| 25, 26 | S | `Do.Project` implementation error | `TAC.management` tested once for the last stock; `TACsStep[6]` recorded the previous TAC | Test per stock; record the implemented TAC | End to end with implementation error on: Target_catch NA → 3048.7 t | [`4023da6`](https://github.com/paulburch/ratpackR/commit/4023da62eb573a8189f378dff7a19fb5b5537298) |
| 27 | S | Equilibrium-catch block | `EarlyDevs[1:MaxAge]`, `R0[1]` linear-indexed on area matrices | `[Iarea, ...]` | Block exercised with an equilibrium-catch copy; identical for 1 area | [`2dd9dfe`](https://github.com/paulburch/ratpackR/commit/2dd9dfe847a9bfb1a603a1c267813573fa71732d) |
| 28 | S | `HybridA`, `Hybrid` | `Stock[[1]]$Nhist` used for every stock | `Stock[[Istock]]$Nhist` | Single stock identical | [`db3ea06`](https://github.com/paulburch/ratpackR/commit/db3ea06994c226b1842bbef6089385180628c12e) |
| 29 | S → confirmed | `HybridA` | Every area closed to a fleet gives 0/0 and a crash | Skip normalising when no area is open (no catch) | End to end: closed-area run crashed, now completes | [`c2c38a9`](https://github.com/paulburch/ratpackR/commit/c2c38a99dcfe40a39322931b5039bdfe3e332e13) |
| 30 | S | `Project.One.Ahead` | `Fout` undefined if `#MSY` is not 2 or 3 | Clear `stop()` message | `#MSY 1` copy now gives the message | [`e21c671`](https://github.com/paulburch/ratpackR/commit/e21c671cd6cc9e3da1b6701ec61e82788779089c) |
| 31 | S | `SPR_ref` | Year-1 M and fecundity used with the current year's selectivity | M and fecundity of `Iyear` | Identical for current inputs (TrueRBC 2504.2 t) | [`5d6fdab`](https://github.com/paulburch/ratpackR/commit/5d6fdaba2ed504059c02da2b0641a065bc093604) |
| 32 | S | `DoRun`, `Run_Tier1a` | `General$Nsim <- 1` and `TheTACs[1] <- 0` made local copies of globals | `<<-` | Identical | [`fb3e871`](https://github.com/paulburch/ratpackR/commit/fb3e8711a780508d36687726eb466ddf2c3effc9) |
| 35 | S | `DataGen.R` | Discards and CAA with several biological areas per assessment area used the wrong or last area | Sum over the assessment area's biological areas | CAA copy: identical for 1 area | [`d012d66`](https://github.com/paulburch/ratpackR/commit/d012d66adb38a49b189f0c717deb678f1b8ad6eb) |
| 36 | S | `DataGen.R` | Deterministic ages not normalised | `Nsamp × Expected / sum(Expected)` | See above | [`5a785b6`](https://github.com/paulburch/ratpackR/commit/5a785b65aab54f5077ec47d387578d13d6cd5c54) |
| 37 | S | `DataGen.R` | CAA used the marginal-age seeds (`CAA.seeds` built but never used) | `CAA.seeds` | CAA copy runs; independent draws | [`3417862`](https://github.com/paulburch/ratpackR/commit/341786292dc45df47f6d672a55f318503027ba0c) |
| 39 | S | `Write_forecast` | `forecast.ss` opened with `append=T`; caps year hard-coded 2019 | New file; `Year + YrOffset + 1` | Identical | [`f23dc2a`](https://github.com/paulburch/ratpackR/commit/f23dc2a48bca57b4b20f70c6e024b83a616aa606) |
| 40 | S | Tier 4a `f2` | `B0(t)` function-call typo (dead branch, `IsDymB0 = 0`) | `B0[t]` | Identical | [`5138a1a`](https://github.com/paulburch/ratpackR/commit/5138a1ac1d8c2c582db972b4a7fad0f5aedd2bbb) |
| 43 | S | `ReadIn.R` | `CVoption` 3 and 4 not implemented (SD stays 0, step-function ALK) | Clear `stop()` message | `CVoption 3` copy now stops with the message | [`3050bc9`](https://github.com/paulburch/ratpackR/commit/3050bc91eee5f5a33f815f9237f23a2ba6ac6354) |

**Left unchanged on purpose:** #33 (TAC roll-over leaves slot 50; harmless), #34 (`DoRun`
returns after one simulation unless `Estimation.test >= 90`; your development behaviour),
#44 (hard-coded 50 forecast years and unused code; a refactor, not a fix), and #38, #41,
#42, which need your input (below).

## Decisions for you

These fixes, or the items left open, depend on what you intended:

1. **#2 Buffer combination.** I made the default and time buffers multiply,
   `max(Min.Buffer, Buffer × (1 − Time × Stale.rate))`. The alternative is
   `Buffer − Time × Stale.rate`.
2. **#5 PGMSY with a zero-catch linked fleet.** I carry over that fleet's TAC, as for an
   unlinked fleet. You may prefer another rule.
3. **#8 Movement age convention.** I changed the three equilibrium routines to use
   `Move[,,Iage]` (the age just reached), as `Project.One.Ahead` does. The alternative is to
   change `Project.One.Ahead` to `Iage−1`.
4. **#14 Tier 5 TAC.** With no TAC management I set the TAC array to 0 (TAC columns are NA
   in the outputs); F comes from `F.fix`.
5. **#15 `CatchType` 3.** I restored your commented-out fill of `F.Selex.Inp` from
   `OM.obj$Fleet.F.data`, giving every open area the same F. Please confirm how F should be
   split across areas. Two input issues came up:
   - `CatchType` 3 can't be combined with `# Initial depletion`: with F fixed, depletion
     doesn't depend on R0, so the R0 search runs to its limit and catches come out 10× too
     high. A check in `DoRun` for this combination would help (not added).
   - Silver warehou's `.OM.SAV` has F = 0 for the last two years although there was catch,
     so `CreateInputs SingleSpecies.R` (around lines 752–764) may not extract F correctly
     for the final years.
6. **#31 `SPR_ref` biology year.** I used the M and fecundity of the year being evaluated.
   If year-1 (unfished-era) biology was intended, revert this commit.
7. **#27, #35 multi-area parts in `Assessment.R`.** `Finitial[Ifleet]` and `Rec_devs[Iyr]`
   (linear indexing on area matrices), and `Write_data` writing discards without an area
   split, were left alone: how biological areas should be combined into the single-area EM
   is a design question.
8. **#38** `if (Ind != Num.Pred+Ind)` in the environmental-index code depends only on
   `Num.Pred`, so with no predators the heatwave override applies to every index. The
   intended condition isn't clear to me.
9. **#41 insurance**: SPR target hard-coded at 0.41, and `Project()` in `Model.cpp` gives each
   sex the full R0. **#42 predators**: the module is unfinished (the `AAAA` stop).
10. **#45 Tier 4a gives RBC = 0 for P.cod.** This is an input problem, not a code bug. In the
    OM, P.cod biomass in 1985–1995 was 85–132% of unfished (because of `#Early_R0Mult`), but
    `#Tier_4a:MSYRY1/2 1985 1995` with `CVMSYL 0.002` forces those years to BMSY = 0.4 K.
    The model then inflates K and estimates current depletion at about 0.1 (true 0.49), so
    the HCR gives 0. Loosening the r prior or CVMSYL doesn't help; the anchor years need
    changing or the MSYL penalty dropping. Related:
    - `Run_Tier4a` passes `eval.max`/`iter.max` to `MakeADFun`, but `nlminb` runs with its
      defaults. Passing them to `nlminb` was tested and not kept (it doesn't change the
      outcome).
    - With deterministic data (`Estimation.test` 1 or 2) the CPUE SD goes to 0 and the fit
      never converges; Tier 4a should be tested with stochastic data (`Estimation.test 99`).
    - `dnorm(log(C), ...)` is −Inf when any historical catch is 0, and Tier 4b uses the true
      OM catch and a hard-coded `/0.48`. Both left as they are.
11. **`R Inserts/Parallel/Assessment.R`** is no longer sourced by anything and can be deleted
    if you agree.

## How the fixes were tested

1. **Reproducible checks** (`docs/bug_checks.R`, about 30 s). Twenty small checks that
   reproduce bugs with synthetic inputs or by calling the code directly. On the unfixed code
   all 20 report CONFIRMED. After each fix, the check for that bug should change to NOT
   REPRODUCED and no other check should change. Some checks run the faulty expression on its
   own (B06, B07, B08, B11, B12, B13, B17, B20); they stay CONFIRMED by design, and the fix
   for those was tested separately.
2. **Smoke runs** (`RunStreams/RunSmokeTest.R`). Silver warehou from `Inputs Buffer/`, one
   simulation, one projection year, Tier 1 with SS: `Estimation.test` 1 (no estimation),
   2 (estimation, deterministic data) and, where relevant, 99 (stochastic data with
   clean-up). Every run had to finish without error.
3. **Output comparison** (`docs/bugfix/compare_runs.R`). Every `Results/*.Out` file was
   compared token by token with the previous step, at a relative tolerance of 1e-8. Re-running
   the unfixed code gave identical output, so every difference could be attributed to a fix,
   and each one was explained (the table above).
4. **End-to-end runs of branches the standard inputs don't reach.** For options no current
   input uses, I made copies of the Silver warehou (or P.cod) inputs with one switch changed,
   and ran old and new code: discard ages (#13), Tier 5 (#14), `CatchType` 3 (#15), Tier 4a
   with `EstR No`/`EstZ Yes` (#16), implementation error (#25/26), equilibrium catch (#27),
   a closed area (#29), `#MSY 1` (#30), CAA data (#35, #37) and `CVoption 3` (#43). Old code
   crashed in #13, #14, #16 and #29; new code completes.
5. **Final regression**, all fixes together against the unfixed baseline: all three smoke
   runs complete, and the only differences are the intended ones listed under "Fixes that
   change results". RBCs in the deterministic runs are identical (8230.1 and 2627.5 t).
6. **Parallel driver** (#17): two simulations at `Estimation.test 99`, serial `DoRun` and
   `DoRunParallel` on two workers, give identical output in all 11 files.
7. **Regression suite** (`tests/run_all.sh`). Runs the checks, E1, E2 and P.cod Tier 4a
   against stored reference outputs (`--full` adds E99 and the 2-simulation parallel run).
   It exits with status 1 on any difference, and was shown to catch a change of 4e-5 in one
   number. It is meant for checking future merges of your updates into my fork.

**Limits of the testing.**
- There is no complete multi-stock or multi-area input set in the repository, so the
  multi-stock and multi-area fixes (#4–#8, #25, #27, #28, #35) were verified only with the
  synthetic checks, plus single-stock runs showing nothing else changed.
- Tier 4b (#12) was not run end to end.
- The test runs and references were made on Linux (Ubuntu 24.04, R 4.5.3, SS 3.30.26).

**Independent re-check (4 November 2026).** Before writing this summary I compared each fix
commit with the review and the log, and read the code changes; they match what is described.
I also re-ran `tests/run_all.sh` on my Windows PC (R 4.4.1, r4ss 1.52.1, the `CodeBase/ss.exe`
in the repository):
- **Checks:** pass; all 20 check statuses are identical to the reference.
- **Tier 4a P.cod:** the projection outputs (RBC, TAC, catch, biomass) are identical to the
  Linux reference. Only the Tier 4a biomass estimates in `Estimates.Out` differ, by up to 5%.
  That is expected: with deterministic data this fit does not converge (#45), so where the
  optimiser stops depends on the platform.
- **E1 and E2 (Silver warehou with SS):** these could not run on Windows. `r4ss::SS_output`
  stops while reading `Report.sso` (`SD_of_devs_over_sigma_R ... replacement has 0 rows`).
  The **unfixed** code stops in the same place, so this comes from the r4ss version not
  matching that `ss.exe` build, not from the fixes. The SS runs were tested on Linux, as
  described above.

A few minor points from reading the code, none of which change results:
- The #15 fill of `F.Selex.Inp` runs for every `CatchType`, not only 3. It is used only for
  `CatchType` 3, so this is harmless, but it could be wrapped in `if (CatchType == 3)`.
- After fix #3 the clean-up condition is in effect just the `Clean.up` setting, because only
  `Estimation.test = 99` reaches that point. On Linux SS writes `ss3.log`, not `ss.log`.
- In #35, a small helper function (`SumUse`) is defined inside the CAA loop; it could be
  moved out.

## If you want to take the fixes

- The fix commits sit on top of a few portability commits (`linux-portability`): the run
  streams and `CreateInputs*.R` read the repository location from `RATPACK_ROOT` (default:
  the working directory) instead of `C:/Research/NewRat/`, the SS call works with the Linux
  executable (`CodeBase/ss3_linux`), and there is a `.gitignore` for `Results/` and `Temp/`.
  If you don't want those, you can take the fixes without them. I checked this by applying the
  code part of each `Fix` commit, in order, to your `main` (`e57b8ca`): 36 of the 38 apply
  cleanly and the five changed R files parse. The two exceptions are small: #23 sits next to
  the SS call that the portability change rewrote, and #17 replaces
  `R Inserts/Parallel/RatpackR.R`, which the portability change also touched.
- Each fix commit also adds its entry to `docs/bugfix/bugfix_log.md`, so a plain
  `git cherry-pick` conflicts on that file; take the R files only. The documentation and tests
  (`docs/bug_review.md`, `docs/bugfix/`, `tests/`, `RunStreams/RunSmokeTest.R`) can be left out.
- Nothing has been pushed to your repository.
