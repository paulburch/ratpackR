# ============================================================================
# fournier_doonan_1987_delaydiff_RTMB.R
#
# RTMB implementation of the generalized (length-based) delay-difference
# stock assessment model of:
#
#   Fournier, D.A. and Doonan, I.J. (1987). A length-based stock assessment
#   method utilizing a generalized delay-difference model.
#   Can. J. Fish. Aquat. Sci. 44: 422-437.  (CSP reprint 2011)
#
# Model summary
# -------------
# The population is divided into G "groups" (Deriso's partial-recruitment
# device).  Recruits (age kage) enter group 1; each year a fish in group g
# moves to group g+1 with probability (1 - m_g) at the END of the year
# ("scheme 2", eqns 5.1-5.4, the scheme used in the paper's simulations).
# The last group retains its fish (m_G = 1).  Fisheries operate
# instantaneously at the START of the year; natural mortality (survival l)
# operates through the year.
#
# Mean length at age lies on a von Bertalanffy curve (eq 10.1):
#     tau_{j+1} = rho * tau_j + (1-rho) * Linf
# and mean weight at age is w_j = bwl * tau_j^3 (eq 9.1, v = 3).
#
# Because tau_j satisfies a first-order difference equation, the moments
#     T^r_{ig} = sum_j tau_j^r N_{ijg},   r = 0,...,4
# satisfy a closed first-order system of difference equations
# (Theorems 3 and 4) -- the population never has to be age-structured.
# All model predictions are functions of the T^r:
#     biomass         B_ig  = bwl * T3_ig                        (eq  9.2)
#     catch weight    C_fi  = sum_g t_fig B_ig                   (eq  9.3)
#     mean weight     M_fi  = C_fi / (sum_g t_fig T0_ig)         (eq  9.4)
#     length moments  from T0..T4 + within-age N(0, sigma_tau^2) noise
#                     (eqns 8.4-8.11)
# Fishing:
#     q_fig = Q1_fg * exp( Q2_fg * (1 - B_ig/B_1g) )             (eq  7.5)
#     s_ig  = exp( -sum_f q_fig E_fi )                           (eq  7.1)
#     t_fig = (q_fig E_fi / Z_ig) * (1 - s_ig)                   (eq  7.2)
# Recruitment (Deriso/Schnute 3-parameter SR, eq 6.1), spawning lagged
# kage years, with RB_1 used for the pre-data years (paper, Step 11):
#     R_i = a * RB * (1 + gamma*beta*(RB/RB_1 - 1))^(-1/gamma) * exp(eps_i)
#     (gamma -> 0 gives Ricker, gamma = 1 gives Beverton-Holt)
#
# Estimation follows the paper's penalized-likelihood / Bayesian scheme:
# lognormal catch, lognormal errors between estimated and effective effort
# (effective efforts are free parameters), normal likelihoods for the mean
# weight and the mean + 2nd-4th central length moments of the catch with
# Kendall & Stuart normal-theory sampling variances, normal/lognormal
# priors on biological parameters (Table 3), and a soft upper bound on the
# group-1 mean length (paper: "necessary to stabilize the estimation").
# The objective is maximized jointly over parameters and deviations
# (posterior mode, as in the paper).  Passing
#     random = c("logEdev","rec_dev")
# to MakeADFun instead gives the Laplace-integrated (mixed-effects) version.
#
# The demo at the bottom re-creates the paper's simulation example
# (two groups, group 1 unavailable, biomass-dependent catchability,
# Ricker recruitment, 20 yr of data) with a FULL age-structured operating
# model, verifies that the delay-difference recursions reproduce the
# age-structured truth to machine precision, and then fits the model.
# ============================================================================

library(RTMB)

# ============================================================================
# 1. The RTMB objective function f_dd(parms, data) lives in
#    R Inserts/DelayDiff.R (shared with the ratpackR EM, Run_DelayDiff).
#    Run this script from the repository root.
# ============================================================================

source("R inserts/DelayDiff.R")
if (!exists("cmb")) cmb <- function(f, d) function(p) f(p, d)

source("MISC HCR/fournier_doonan_sim.R")

# ============================================================================
# 3. Demo: simulate, verify, fit
# ============================================================================

set.seed(101)
Nyr  <- 20
sim  <- sim_fd(Nyr = Nyr)
tp   <- sim$pars
Ngrp <- 2; Nfleet <- 1

avail <- matrix(c(0, 1), Nfleet, Ngrp)     # group 1 unavailable to the fishery
mat   <- c(0, 1)                           # group 2 = reproductive biomass

data <- list(
  Cobs  = matrix(sim$Cobs, 1, Nyr),  Eobs  = matrix(sim$Eobs, 1, Nyr),
  Mobs  = matrix(sim$Mobs, 1, Nyr),  s2w   = matrix(sim$s2w, 1, Nyr),
  L1obs = matrix(sim$L1obs,1, Nyr),  L2obs = matrix(sim$L2obs,1, Nyr),
  L3obs = matrix(sim$L3obs,1, Nyr),  L4obs = matrix(sim$L4obs,1, Nyr),
  nsamp = matrix(tp$nsamp, 1, Nyr),
  avail = avail, mat = mat,
  kage = tp$kage, Amax = tp$Amax, gamma_sr = tp$gamma_sr, bwl = tp$bwl,
  sigmaC = 0.02, sigmaE = tp$sigE, sigmaR = tp$sigR,
  lamM = 1, lamL = rep(1, 4),
  UsePriors = 1,
  prRho   = c(0.863, 0.10),  prL    = c(0.80, 0.10),   # Table 3
  prEntry = c(0.40,  0.10),  prTauk = c(5.0,  0.70),
  prQ1    = c(0.0036, 0.70), prQ2   = c(0.75, 0.70),
  maxlen_g1 = 7.0, lamPen = 100
)

# --- initial parameter values (Bayesian prior means + crude scaling) --------
# per-recruit equilibrium (numeric) to scale R1 and the SR productivity `a`
eq_pr <- function(rho, Linf, tauk, l, m, b, kage, Amax) {
  G <- length(m); nv <- c(1, rep(0, G-1)); tau <- tauk
  T3g <- rep(0, G); T0g <- rep(0, G)
  for (j in kage:Amax) {
    T0g <- T0g + nv; T3g <- T3g + tau^3 * nv
    nn <- m * l * nv
    if (G > 1) nn[2:G] <- nn[2:G] + (1 - m[1:(G-1)]) * l * nv[1:(G-1)]
    nv <- nn; tau <- rho*tau + (1-rho)*Linf
  }
  list(B = b * T3g, N = T0g)
}
init <- list(rho = 0.863, Linf = 13.0, tauk = 5.0, l = 0.80,
             entry = 0.40, Q1 = 0.0036, Q2 = 0.75, beta = 1.0)
pr    <- eq_pr(init$rho, init$Linf, init$tauk, init$l,
               c(1 - init$entry, 1), data$bwl, data$kage, data$Amax)
Bfish_target <- data$Cobs[1,1] / (1 - exp(-init$Q1 * data$Eobs[1,1]))
R1_init <- Bfish_target / pr$B[2]
a_init  <- 1 / sum(mat * pr$B)             # virgin consistency: a = 1/SPR_mat

parameters <- list(
  logR1 = log(R1_init), loga = log(a_init), logbeta = log(init$beta),
  logit_rho = qlogis(init$rho), logLinf = log(init$Linf), tauk = init$tauk,
  logit_l = qlogis(init$l), logit_m = qlogis(1 - init$entry),
  logQ1 = matrix(log(init$Q1), Nfleet, Ngrp),
  Q2    = matrix(init$Q2,      Nfleet, Ngrp),
  log_sigma_tau = log(tp$sigtau),
  logEdev = matrix(0, Nfleet, Nyr),
  rec_dev = rep(0, Nyr - 1)
)
avail_map <- rep(NA, length(avail))       # estimate q only where available
avail_map[avail == 1] <- seq_len(sum(avail))
map <- list(
  logQ1 = factor(avail_map),
  Q2    = factor(avail_map),
  log_sigma_tau = factor(NA)              # known from ageing (paper, Step 1)
)

# ----------------------------------------------------------------------------
# VERIFICATION: at the true parameters (and true deviations) the
# delay-difference model must reproduce the age-structured operating model
# exactly (Theorems 1-4).
# ----------------------------------------------------------------------------
true_parameters <- list(
  logR1 = log(tp$R1), loga = log(tp$a_sr), logbeta = log(tp$beta),
  logit_rho = qlogis(tp$rho), logLinf = log(tp$Linf), tauk = tp$tauk,
  logit_l = qlogis(tp$lsurv), logit_m = qlogis(tp$mstay[1]),
  logQ1 = matrix(log(tp$Q1), Nfleet, Ngrp),
  Q2    = matrix(tp$Q2,      Nfleet, Ngrp),
  log_sigma_tau = log(tp$sigtau),
  logEdev = matrix(log(sim$Etrue) - log(sim$Eobs), Nfleet, Nyr),
  rec_dev = sim$rec_dev[2:Nyr]
)
map_all <- lapply(true_parameters, function(x) factor(rep(NA, length(x))))
map_all$logR1 <- NULL                     # need >= 1 free parameter
obj0 <- MakeADFun(cmb(f_dd, data), true_parameters, map = map_all, silent = TRUE)
rp0  <- obj0$report()
relerr <- function(x, y) max(abs(x - y) / (abs(y) + 1e-12))
cat("\n--- Verification: delay-difference vs age-structured truth ---\n")
cat(sprintf("  catch weight : %.2e\n", relerr(rp0$Chat[1,],  sim$Ctrue)))
cat(sprintf("  mean weight  : %.2e\n", relerr(rp0$Mhat[1,],  sim$Mw_true)))
cat(sprintf("  mean length  : %.2e\n", relerr(rp0$L1hat[1,], sim$L_true[1,])))
cat(sprintf("  2nd c.moment : %.2e\n", relerr(rp0$L2hat[1,], sim$L_true[2,])))
cat(sprintf("  3rd c.moment : %.2e\n", relerr(rp0$L3hat[1,], sim$L_true[3,])))
cat(sprintf("  4th c.moment : %.2e\n", relerr(rp0$L4hat[1,], sim$L_true[4,])))
cat(sprintf("  biomass      : %.2e\n", relerr(rp0$Bmat,      sim$B)))
cat(sprintf("  recruitment  : %.2e\n", relerr(rp0$Rrec,      sim$R)))

# ----------------------------------------------------------------------------
# FIT (posterior mode over parameters and deviations, as in the paper).
# For the Laplace-integrated mixed-effects version use:
#   MakeADFun(cmb(f_dd, data), parameters, map=map, random=c("logEdev","rec_dev"), ...)
# ----------------------------------------------------------------------------
model <- MakeADFun(cmb(f_dd, data), parameters, map = map,
                   control = list(eval.max=10000, iter.max=1000), silent = TRUE)
fit <- nlminb(model$par, model$fn, model$gr,
              control = list(eval.max=10000, iter.max=1000))
for (i in 1:5) fit <- nlminb(model$env$last.par.best, model$fn, model$gr,
                             control = list(eval.max=10000, iter.max=1000))
cat(sprintf("\nConverged: %s   objective = %.3f   max|grad| = %.2e\n",
            fit$message, fit$objective, max(abs(model$gr(fit$par)))))

rep  <- sdreport(model)
rep2 <- summary(rep)
rp   <- model$report()

# --- compare leading parameters to the truth --------------------------------
getp <- function(nm) rep2[rownames(rep2) == nm, , drop=FALSE]
cmp <- rbind(
  rho    = c(tp$rho,      getp("rho")[1,]),
  Linf   = c(tp$Linf,     getp("Linf")[1,]),
  tauk   = c(tp$tauk,     getp("tauk")[1,]),
  l      = c(tp$lsurv,    getp("lsurv")[1,]),
  m1     = c(tp$mstay[1], getp("mstay")[1,]),
  Q1     = c(tp$Q1,       getp("Q1a")[1,]),
  Q2     = c(tp$Q2,       getp("Q2a")[1,]),
  a_sr   = c(tp$a_sr,     getp("a_sr")[1,]),
  beta   = c(tp$beta,     getp("beta")[1,]),
  R1     = c(tp$R1,       getp("R1")[1,]),
  DeplFin= c(sim$B[2,Nyr]/sim$B[2,1], getp("Depl")[Nyr,])
)
colnames(cmp) <- c("true", "estimate", "SE")
cat("\n--- Parameter recovery ---\n")
print(round(cmp, 4))

# --- plots ------------------------------------------------------------------
dir.create("Temp", showWarnings = FALSE)
pdf("Temp/fournier_doonan_RTMB_fit.pdf", width = 10, height = 7)
par(mfrow = c(2,3), mar = c(4,4,2,1))
yrs <- 1:Nyr
plot(yrs, sim$Cobs, pch=16, xlab="Year", ylab="Catch weight",
     main="Catch", ylim=c(0, 1.1*max(sim$Cobs)))
lines(yrs, rp$Chat[1,], col=2, lwd=2)
plot(yrs, sim$Mobs, pch=16, xlab="Year", ylab="Mean weight",
     main="Mean weight of catch", ylim=c(0, 1.1*max(sim$Mobs)))
lines(yrs, rp$Mhat[1,], col=2, lwd=2)
plot(yrs, sim$L1obs, pch=16, xlab="Year", ylab="Mean length",
     main="Mean length of catch", ylim=c(0, 1.1*max(sim$L1obs)))
lines(yrs, rp$L1hat[1,], col=2, lwd=2)
plot(yrs, sim$B[2,], type="l", lwd=2, xlab="Year", ylab="Biomass",
     main="Fishable biomass", ylim=c(0, 1.1*max(sim$B[2,])))
lines(yrs, rp$Bmat[2,], col=2, lwd=2, lty=2)
legend("topright", c("true","estimated"), col=c(1,2), lty=c(1,2), lwd=2, bty="n")
plot(yrs, sim$R, type="l", lwd=2, xlab="Year", ylab="Recruitment",
     main="Recruitment", ylim=c(0, 1.1*max(sim$R)))
lines(yrs, rp$Rrec, col=2, lwd=2, lty=2)
plot(yrs, sim$q, type="l", lwd=2, xlab="Year", ylab="q",
     main="Catchability (biomass-dependent)", ylim=c(0, 1.1*max(sim$q)))
lines(yrs, rp$qsave[2,], col=2, lwd=2, lty=2)
dev.off()
cat("\nPlots written to Temp/fournier_doonan_RTMB_fit.pdf\n")
