# Running ratpackR on Linux (cloud set-up)

This note explains how ratpackR was made to run on Linux in a Claude Code cloud container
(Ubuntu 24.04, x86-64, 4 cores, 16 GB RAM), and how to repeat the set-up. Everything is
scripted in [`setup_linux.sh`](../setup_linux.sh).

## 1. Quick start

```bash
bash setup_linux.sh
```

```bash
source "$HOME/ratpack-env/activate.sh"
```

```bash
Rscript RunStreams/RunSmokeTest.R 1 1
```

The first command installs everything (about 3.5 minutes; most of that is compiling RTMB).
The second puts R on the `PATH` for the current shell. The third runs a one-simulation,
one-projection-year smoke test (about 1.5 minutes).

## 2. What `setup_linux.sh` installs, and why

| Step | What | Why this route |
|---|---|---|
| 1 | `micromamba` 2.10.0 (one static binary from `conda.anaconda.org`) | No root access or system R needed |
| 2 | conda-forge environment `ratpack`: `r-base` 4.5, `gcc/gxx/gfortran_linux-64`, `make`, `r-rcpp`, `r-rcpparmadillo`, `r-rcppeigen`, `r-tmb`, `r-matrix`, `r-readxl`, the r4ss dependencies (`dplyr` ≥ 1.2, `ggplot2`, `tidyr`, `purrr`, …), `r-foreach`, `r-doparallel` | Binary packages, so the install is fast, and the compilers are the ones conda's R is configured to use for `Rcpp::sourceCpp` |
| 3a | **RTMB 2.0** built from source from `github.com/cran/RTMB` (tag `2.0`, the CRAN release mirror) | RTMB is not on conda-forge |
| 3b | **r4ss 1.56.0** built from source from `github.com/r4ss/r4ss` (tag `v1.56.0`) | The current r4ss is distributed through GitHub. The CRAN `r4ss` (1.44.1) is now only a compatibility notice with no functions |
| 4 | `~/ratpack-env/activate.sh` | Activates the environment in a new shell |
| 5 | Load check: prints the package versions and compiles a one-line `RcppArmadillo` function | Shows that `sourceCpp` works before a long run starts |

**Why not CRAN or apt?** The network policy of the cloud environment used for this work
blocked `cloud.r-project.org`, `cran.r-project.org`, Posit Package Manager, r-universe and
GitHub release tarballs. It allowed `conda.anaconda.org` and `git clone` from `github.com`.
On a machine with CRAN access, the same thing can be done with the system R and
`install.packages(c("Rcpp","RcppArmadillo","RTMB","remotes")); remotes::install_github("r4ss/r4ss")`,
plus a C++ compiler (`build-essential`).

Versions installed in the run of 2 November 2026:

```
R 4.5.3 (2026-03-11)   r4ss 1.56.0   RTMB 2.0   Rcpp 1.1.2   RcppArmadillo 15.6.2.1
```

The script takes `RATPACK_ENV` (install location, default `~/ratpack-env`), `R4SS_REF` and
`RTMB_REF` (git tags) as environment variables, and it can be re-run safely.

## 3. Changes made to André's code for portability

The changes are kept minimal so that `git pull upstream main` stays clean. The files keep
their Windows (CRLF) line endings.

1. **Working-directory root.** Every `RunStreams/*.R` script had
   `Path <- "C:/Research/NewRat/NewRat_spat/"`. It is now
   `Path <- sub("/*$", "/", Sys.getenv("RATPACK_ROOT", unset = getwd()))`. Run the scripts from
   the repo root, or set `RATPACK_ROOT`. A trailing `/` is always added.
2. **Input-creation scripts.** These need two roots: the repo, and the folder holding the
   `Base * files/` SS3 assessments (which are not in the repo).
   - `Repo <- ... Sys.getenv("RATPACK_ROOT", unset = getwd())`
   - `Path <- ... Sys.getenv("RATPACK_BASE", unset = dirname(Repo))`. The default matches
     André's layout, where `C:/Research/NewRat/` contains `NewRat_spat/`.
   - All `"…/Newrat_spat/…"` paths now use `Repo`.
3. **Case-sensitive file names**, which Windows ignores but Linux does not:
   - `source("RatPackR.r")` becomes `source("RatpackR.R")` in every run stream.
   - `"R inserts/Readin.R"`, `"R inserts/…"` become `"R Inserts/ReadIn.R"`, `"R Inserts/…"` in
     `RatpackR.R` and `R Inserts/Parallel/RatpackR.R`.
   - `ExtraCatches.Csv`, `fleet-metierv0/1.csv` become `ExtraCatches.csv` and
     `Fleet-metierV0/1.csv` (`CreateInputs *.R`).
   - `RunCaitlinM.R` read `"Inputs CAITLINM/"`, but `CreateInputs Multispecies.R` writes
     `"Inputs CaitLinM/"`. The run stream now uses `"Inputs CaitLinM/"`.
   - In the SS clean-up step, `Report.SSO`, `compreport.sso` and `cumreport.sso` become
     `Report.sso`, `CompReport.sso` and `CumReport.sso`, the names SS 3.30 writes.
4. **Stock Synthesis executable** (`Run_Tier1a` in `R Inserts/Assessment.R`, and the same code
   in `R Inserts/Parallel/Assessment.R`). The code copied `CodeBase/SS.exe` into each EM folder
   and ran `system("SS")`. It now chooses by platform:

   ```r
   SS.exe <- if (.Platform$OS.type == "windows") "SS.exe" else "ss3"
   SS.cmd <- if (.Platform$OS.type == "windows") "SS" else "./ss3"
   File.from <- paste0(Path,"CodeBase/",if (.Platform$OS.type == "windows") "ss.exe" else "ss3_linux")
   ```

   On Linux, `CodeBase/ss3_linux` is copied in as `ss3`. ADMB names its output files after the
   executable, so SS then writes `ss3.par`, `ss3.rep`, `ss3.log`, matching what the R code
   reads (`ss3.par`) and deletes. Windows behaviour is unchanged.

`CodeBase/ss3_linux` reports **Stock Synthesis V3.30.26.00, safe build, compiled 29 Oct 2026,
ADMB 13.2** (first line of `Report.sso`). It is a statically linked x86-64 ELF executable.

## 4. Smoke test (`RunStreams/RunSmokeTest.R`)

```bash
Rscript RunStreams/RunSmokeTest.R <Estimation.test> <Nproj> ["source input folder"]
```

The script copies the Silver.warehou input files into `Temp/SmokeInputs/` (git-ignored),
sets `#Number_of_simulations 1` and `#Number_of_projection_years <Nproj>`, sets the same run
flags as `RunCSIRO.R`, and calls `DoRun()`.

**The `Inputs CSIRO/` set for Silver.warehou is incomplete.** Only
`General_Silver.warehou.OM` is in the repository, in both the fork and upstream `main`.
`Silver.warehou.OM`, `.EM`, `.OM.SAV` and `.EM.SAV` are missing; `RunCSIRO.R` fails with
`cannot open file 'Inputs CSIRO/Silver.warehou.OM'`. The same files are also missing for
School.whiting, Tiger.flathead and (partly) Redfish. The smoke test therefore uses the complete
Silver.warehou set in `Inputs Buffer/` (the `RunBuffer.R` set-up) by default.

Results on 4 cores. Every run used 1 simulation and 1 projection year with one assessment
(model year 46); the historical OM projection plus the 10-step R0 search take about 60 s of
each run:

| Run | `Estimation.test` | What SS did | Wall time | Result |
|---|---|---|---|---|
| no estimation | 1 | ran from `ss3.par`, max phase 0 | 78 s (87 s with start-up) | completed; all 13 `Results/` files written. SS read the `.par` file exactly: all 147 values in `ss3.par` equal the input `ss3a.par` |
| with estimation | 2 (deterministic data) | estimated 42 parameters, final max gradient 1.8e-5 | 88 s (98 s with start-up) | completed; TAC changed from 1726/5000 t to 551/1596 t on the two open fleets |
| real | 99 | estimated 42 parameters from stochastic data, max gradient 2.9e-5 | 95 s (106 s with start-up) | completed; the EM folder still holds the `ss3` binary and the `.sso` files, because the clean-up block never runs (bug review #3) |

Warnings seen in these runs (details in `docs/bug_review.md`):
`NAs introduced by coercion` in `SetSpec` (economics `FixedCosts`, B02); a column-count
warning from `rbind` on `LengthData` (B18); `cannot remove file 'FALSE'` from
`file.remove("ss3par.par", showWarnings=F)`; and `longer object length…` in `WriteInsurance`.

## 5. Practical notes

- **Disk:** every EM folder (`Temp/Assess_temp_<run>/SS_Sim_*`) is about 11 MB, including a
  7 MB copy of the SS executable. In practice nothing is deleted: development runs (0–6)
  return before the clean-up, and for `Estimation.test == 99` the main clean-up block is
  skipped (bug review #3). Delete `Temp/` between runs.
- **Runs stop after one simulation** unless `Estimation.test >= 90` (`DoRun`:
  `if (Estimation.test < 90) return()`).
- **Long runs:** use `nohup Rscript RunStreams/RunX.R > run.log 2>&1 &`. The run streams need
  the working directory to be the repo root, or `RATPACK_ROOT` set.
- **Parallel version:** `R Inserts/Parallel/RatpackR.R` needs `n_cores` to be defined. It is an
  older copy of the engine (see bug review B17 and the drift section), so do not expect it to
  reproduce the serial results.
- **Line endings:** the repository stores CRLF. Edit with an editor that keeps CRLF, so that
  diffs against upstream do not show every line as changed.
