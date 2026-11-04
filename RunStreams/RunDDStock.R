rm(list=ls())
# Delay-difference EM (Tier_DD, R Inserts/DelayDiff.R) test for any stock in Inputs DD/:
#   Rscript RunStreams/RunDDStock.R <Stock> [Estimation.test]
# Inputs other than Morwong are made by MISC HCR/make_DD_inputs.R.  Morwong:
# 1 area, 1 sex.  Inputs DD/ is a copy of the Morwong inputs in Inputs CSIRO/
# with the EM switched to Tier_DD, 1 simulation, 10 projection years and an
# assessment every 3 years.  Run from the repository root.
Path <- sub("/*$", "/", Sys.getenv("RATPACK_ROOT", unset = getwd()))
setwd(Path)

library(r4ss)
library(RTMB)
library(RcppArmadillo)
library(Rcpp)

source("RatpackR.R")


# =========================================================================================================================
# =========================================================================================================================

# Is this a test run
TestCase <- F
IsJitter <- F
Deter.Rec.devs <- F
Deter.Index.data <- F
Deter.Discard.data <- F
Deter.Length.data <- F
Deter.Age.data <- F
Huge.sample.sizes <- F


# 99 is actual
FullOutput <- T
Estimation.test <- 99                  #(0: Development; 1: Deterministic and no estimation ;2: Deterministic;
                                       #3: Deterministic (incl rec_devs); 5: Huge sample sizes and no estimation;
                                       #99: Real )
Args <- commandArgs(trailingOnly=TRUE)
Stock.Name <- if (length(Args) > 0) Args[1] else "Morwong"
if (length(Args) > 1) Estimation.test <- as.numeric(Args[2])

if (Estimation.test %in% c(1,2)) { Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }
if (Estimation.test %in% c(3)) { Deter.Rec.devs <- T; Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }
if (Estimation.test %in% c(4)) { Huge.sample.sizes <- T }
if (Estimation.test %in% c(5)) { Huge.sample.sizes <- T }
if (Estimation.test %in% c(6)) { Huge.sample.sizes <- T; Deter.Index.data <- T; Deter.Discard.data <- T; Deter.Length.data <- T; Deter.Age.data <- T }

# RATPACK_DD_INPUTS: another input folder (e.g. a copy with more simulations);
# RATPACK_DD_TAG: suffix for the results folder
Input.Folder <- Sys.getenv("RATPACK_DD_INPUTS", unset="Inputs DD/")

DoRun(GeneralFile=paste0("General_",Stock.Name,".OM"),RunNo=paste0(Stock.Name,".DD",Sys.getenv("RATPACK_DD_TAG")))
