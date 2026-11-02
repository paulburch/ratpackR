# ratpackR

R management strategy evaluation (MSE) framework by André Punt ("NewRat"), applied to SESSF stocks. An operating model (OM) projects one or more stocks forward; each year an estimation model (EM, built from Stock Synthesis inputs) is fitted, a harvest control rule sets RBCs/TACs, and the TACs are adjusted (buffers, multispecies PGMSY, indicator species, insurance) before the next projection year.

## Repository and git

- Paul's fork: `origin` = https://github.com/paulburch/ratpackR (public, personal account). Upstream: `upstream` = https://github.com/puntae/ratpackR (André Punt's repo; never push there).
- Commits use the personal identity set in this repo's local git config (`Paul Burch <6994305+paulburch@users.noreply.github.com>`); never the work GitHub account.
- Get André's updates with `git pull upstream main`. Keep Paul's changes on branches so upstream merges stay clean; avoid reformatting or reorganising André's files, so diffs against upstream stay small.
- The fork is public: no confidential data, AFMA data or unreleased results go in the repo.

## Layout

- `RatpackR.R`: the main engine. Sources `R Inserts/ReadIn.R`, `WriteOut.R`, `Assessment.R`, `DataGen.R` and compiles `R Inserts/Model.cpp` with `Rcpp::sourceCpp`. Entry point is `DoRun(GeneralFile, RunNo)`; other key functions are `Read.General.File`, `Do.Project`, `Project.One.Ahead`, `Solve.for.multispecies.F`, `PGMSY`, `AdjustTACS`, `GetRefs`.
- `R Inserts/`: the sourced modules (read-in, assessment/EM fitting, data generation, output writers, `SaveFiles.R` for writing OM/EM input files), the C++ model and utilities; `Parallel/` holds parallel versions of `RatpackR.R` and `Assessment.R`.
- `RunStreams/`: driver scripts, one per set of runs (`RunCSIRO.R`, `RunCSIROM.R` multispecies, `RunBuffer.R`, `RunArea.R`, `RunWAsharksM.R`, etc.). Each sets run flags (`Estimation.test`, deterministic switches, `Input.Folder`) and calls `DoRun()` for chosen stocks.
- `Inputs CSIRO/`, `Inputs CSIROM/`, `Inputs Buffer/`, `Inputs Other/`, `Inputs OtherM/`: per-stock input files. `General_<Stock>.OM` is the general run file passed to `DoRun`; `<Stock>.OM` and `<Stock>.EM` are the operating and estimation model specs (`.SAV` are backups).
- `CreateInputs SingleSpecies.R`, `CreateInputs Multispecies.R`: build the input files from existing SS3 assessments (via `r4ss`).
- `Check.Setup.R`: compares the OM with the original SS assessment and the EM estimates.
- `CodeBase/ss.exe`: Stock Synthesis executable used for the EM.
- `MISC HCR/`: dynamic Tier 4 HCR code (RTMB and TMB `.cpp`) and an old ADMB Deriso model (`gbr7`); `Misc code/`: extraction and plotting scripts.
- Top-level CSVs (`Fleet-metierV*.csv`, `ExtraCatches.csv`, `WASharks.csv`, `Caitlin.csv`) are inputs for particular run streams.
- Runs write to `Results/` and `Temp/` (relative to the working directory); these are not in git.

## Running

- R packages: `r4ss`, `RTMB`, `Rcpp`, `RcppArmadillo` (and `readxl` for input creation). Needs Rtools for `sourceCpp`.
- Scripts expect the working directory to be the repo root (they `source("RatPackR.r")` and `"R inserts/..."` relatively).
- **Hard-coded paths:** the run streams and input-creation scripts `setwd()` to André's folders (`C:/Research/NewRat/` or `C:/Research/NewRat/NewRat_spat/`). To run here, change `Path` to `C:/_AI/Claude_code/ratpackR/` in a local copy or on a branch, not in a commit meant for upstream.
- Run from the command line with `Rscript "RunStreams/RunCSIRO.R"` after fixing `Path`; full runs can take a long time, so run them in the background.
