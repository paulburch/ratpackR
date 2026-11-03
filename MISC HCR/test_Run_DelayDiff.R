# ============================================================================
# test_Run_DelayDiff.R -- end-to-end test of the ratpackR delay-difference EM
# (Run_DelayDiff in R Inserts/DelayDiff.R) without the operating model.
#
# Simulates a 40-year fishery with the age-structured model in
# fournier_doonan_sim.R, packs the data into a mock Stock object in
# ratpackR's layout (Catches, IndexData.Used, LengthData.Used with years
# offset, binned length comps), with the CPUE index missing for the first
# 10 years and length comps missing for the first 15 years and two later
# years, then runs Run_DelayDiff as Run_Assessment would and compares the
# estimated depletion with the truth.  Run from the repository root.
# Seed 202 happens to be a weakly informative draw (final depletion
# estimated ~0.65 vs 0.28 true); over seeds 301-310 the median relative
# error is about +9% (test_DelayDiff_seeds.R).  This script checks the
# wiring, not estimation performance.
# ============================================================================

library(RTMB)
source("R inserts/DelayDiff.R")
if (!exists("cmb")) cmb <- function(f, d) function(p) f(p, d)
source("MISC HCR/fournier_doonan_sim.R")

set.seed(202)
Nyr <- 40
lobins <- seq(0, 25, by = 0.5)
Etrue <- c(seq(5, 50, length = 25), seq(48, 30, length = 15))
sim <- sim_fd(Nyr = Nyr, Etrue = Etrue, lobins = lobins, nsamp = 300)
tp <- sim$pars

# --- mock ratpackR objects ---------------------------------------------------
YrOffset <- 1950
idx_years <- 11:Nyr
len_years <- setdiff(16:Nyr, c(25, 30))

IndexData <- array(0, dim = c(1, length(idx_years), 5))
IndexData[1,,1] <- idx_years + YrOffset
IndexData[1,,3] <- 1
IndexData[1,,4] <- sim$Cobs[idx_years] / sim$Eobs[idx_years]   # CPUE = C / effort
IndexData[1,,5] <- 0.2

LengthData <- t(sapply(len_years, function(y)
  c(1, y + YrOffset, 7, 1, 0, 0, sum(sim$Lcomp[y,]), sim$Lcomp[y,])))

Stock <- list(list(
  Nsex = 1, LoLenBin = lobins, WtLen_a = tp$bwl, WtLen_b = 3,
  YrOffset = YrOffset, Nhist = 30,
  Data = list(Catches = array(sim$Cobs, dim = c(1, 1, Nyr)),
              IndexData.Used = IndexData, LengthData.Used = LengthData),
  Ass = list(
    SSB.estimates  = array(NA, dim = c(1, 20, 10, Nyr + 10)),
    Depl.estimates = array(NA, dim = c(1, 20, 10, Nyr + 10)),
    DD = list(Cpue_Area=1, Cpue_Index=1, Len_Area=1, Len_Fleet=1, Len_Part=0, MaxNsamp=1000,
              kage=tp$kage, Amax=tp$Amax, gamma_sr=tp$gamma_sr,
              sigmaC=0.05, sigmaE=0.3, sigmaR=0.3, lamM=0, lamL=c(1,1,1,1),
              Rho=c(0.863,0.1), Surv=c(0.8,0.1), Entry=c(0.4,0.1), Tauk=c(5,0.7),
              Q2=c(0.75,0.7), Sigtau=tp$sigtau, Linf_init=13, beta_init=1,
              EstBeta="Yes", EstLinf="Yes", EstQ2="Yes",
              MaxLen_g1=7, lamPen=100, B0_init_mult=10, Q1sd=-1, RecDevLead=3,
              Dlim=0.2, Dtarg=0.48, Htarg=0.1))))

# --- run as Run_Assessment would (two assessment years) ---------------------
DeplTrue <- sim$B[2,] / sim$B[2,1]
res <- list()
for (Year in c(35, 40)) {
  t0 <- Sys.time()
  TACs <- Run_DelayDiff(1, 1, Year)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  DeplEst <- Stock[[1]]$Ass$Depl.estimates[1, Year - 30 + 1, 1, 1:Year] / 100
  res[[as.character(Year)]] <- DeplEst
  cat(sprintf("Year %d: %.1f s; final depletion est %.3f true %.3f; max |est-true| %.3f\n",
              Year, el, DeplEst[Year], DeplTrue[Year], max(abs(DeplEst - DeplTrue[1:Year]))))
  cat("  first 5 RBCs:", round(TACs[1:5], 1), " (last catch", round(sim$Cobs[Year], 1), ")\n")
  stopifnot(length(TACs) == 50, all(is.finite(TACs)), all(TACs >= 0),
            all(is.finite(DeplEst)))
}

dir.create("Temp", showWarnings = FALSE)
pdf("Temp/test_Run_DelayDiff.pdf", width = 8, height = 5)
plot(1:Nyr, DeplTrue, type = "l", lwd = 2, ylim = c(0, 1.2),
     xlab = "Year", ylab = "Fishable biomass / unfished", main = "Run_DelayDiff test")
lines(1:35, res[["35"]], col = 4, lwd = 2, lty = 2)
lines(1:40, res[["40"]], col = 2, lwd = 2, lty = 2)
legend("topright", c("true", "EM year 35", "EM year 40"),
       col = c(1, 4, 2), lty = c(1, 2, 2), lwd = 2, bty = "n")
dev.off()
cat("Plot written to Temp/test_Run_DelayDiff.pdf\n")
