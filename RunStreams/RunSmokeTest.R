# Minimal smoke test (Paul's addition, not part of André's run streams).
# Runs Silver.warehou with 1 simulation and NPROJ projection
# years, using copies of the input files placed under Temp/ (git-ignored), so the
# committed inputs are never modified.
# NOTE: "Inputs CSIRO/" only has General_Silver.warehou.OM (Silver.warehou.OM/.EM/.SAV
# are missing in both the fork and upstream main), so the complete copy in
# "Inputs Buffer/" (the RunBuffer.R set-up) is used by default.
#
# Usage (from the repo root):
#   Rscript RunStreams/RunSmokeTest.R [Estimation.test] [Nproj] [source input folder]
#   e.g. Rscript RunStreams/RunSmokeTest.R 1 1    # no estimation
#        Rscript RunStreams/RunSmokeTest.R 2 1    # deterministic data, with estimation
rm(list=ls())
options(warn = 1)   # print warnings as they occur
Path <- sub("/*$", "/", Sys.getenv("RATPACK_ROOT", unset = getwd()))
setwd(Path)

args <- commandArgs(trailingOnly = TRUE)
Estimation.test <- if (length(args) >= 1) as.numeric(args[1]) else 1
NPROJ <- if (length(args) >= 2) as.numeric(args[2]) else 1
Source.Folder <- if (length(args) >= 3) args[3] else "Inputs Buffer/"
Species <- "Silver.warehou"

library(r4ss)
library(RTMB)
library(RcppArmadillo)
library(Rcpp)

# --- make a reduced copy of the inputs ---------------------------------------
Input.Folder <- "Temp/SmokeInputs/"
dir.create(paste0(Path, Input.Folder), recursive = TRUE, showWarnings = FALSE)
for (f in c(paste0("General_", Species, ".OM"), paste0(Species, c(".OM", ".EM", ".OM.SAV", ".EM.SAV"))))
  file.copy(paste0(Path, Source.Folder, f), paste0(Path, Input.Folder, f), overwrite = TRUE)
GenFile <- paste0(Path, Input.Folder, "General_", Species, ".OM")
Gen <- readLines(GenFile)
Gen <- sub("^#Number_of_simulations.*", "#Number_of_simulations 1", Gen)
Gen <- sub("^#Number_of_projection_years.*", paste("#Number_of_projection_years", NPROJ), Gen)
writeLines(Gen, GenFile)

source("RatpackR.R")

# --- run flags (same logic as RunStreams/RunCSIRO.R) --------------------------
TestCase <- F
IsJitter <- F
Deter.Rec.devs <- F
Deter.Index.data <- F
Deter.Discard.data <- F
Deter.Length.data <- F
Deter.Age.data <- F
Huge.sample.sizes <- F
FullOutput <- T
if (Estimation.test %in% c(1,2)) { Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }
if (Estimation.test %in% c(3)) { Deter.Rec.devs <- T; Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }
if (Estimation.test %in% c(4)) { Huge.sample.sizes <- T }
if (Estimation.test %in% c(5)) { Huge.sample.sizes <- T }
if (Estimation.test %in% c(6)) { Huge.sample.sizes <- T; Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }

RunNo <- paste0("Smoke_", Species, "_E", Estimation.test)
t0 <- proc.time()
DoRun(GeneralFile = paste0("General_", Species, ".OM"), RunNo = RunNo)
cat("SMOKE TEST FINISHED: Estimation.test =", Estimation.test, " Nproj =", NPROJ,
    " elapsed =", round((proc.time() - t0)[["elapsed"]], 1), "s\n")
print(list.files(paste0(Path, "Results/", RunNo)))
