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
# 1. The RTMB objective function
#    (expects a list `data` in the global environment, their-style getAll)
# ============================================================================

f_dd <- function(parms) {
  getAll(data, parms, warn = FALSE)

  Nyr    <- ncol(Cobs)
  Nfleet <- nrow(Cobs)
  Ngrp   <- ncol(avail)

  # --- transform parameters ------------------------------------------------
  R1     <- exp(logR1)                    # virgin (year-1 equilibrium) recruitment
  a_sr   <- exp(loga)                     # SR productivity (eq 6.1)
  beta   <- exp(logbeta)                  # SR density-dependence (eq 6.1)
  rho    <- 1/(1 + exp(-logit_rho))       # vB Brody coefficient (eq 10.1)
  Linf   <- exp(logLinf)                  # vB asymptotic length
  lsurv  <- 1/(1 + exp(-logit_l))         # natural survival (all groups)
  mstay  <- rep(1, Ngrp)                  # P(remain in group); m_G = 1
  if (Ngrp > 1) mstay[1:(Ngrp-1)] <- 1/(1 + exp(-logit_m))
  Q1     <- exp(logQ1) * avail            # constant catchability component
  Q2m    <- Q2 * avail                    # biomass-dependent component
  sigtau <- exp(log_sigma_tau)            # within-age SD of length
  st2    <- sigtau^2

  phi  <- (1 - rho) * Linf                # tau_{j+1} = rho*tau_j + phi
  lvec <- rep(lsurv, Ngrp)

  # --- effective effort (free parameters, eq 2.5 + effort penalty) ---------
  Ehat <- Eobs * exp(logEdev)             # Nfleet x Nyr

  # --- storage -------------------------------------------------------------
  T0 <- matrix(0, Ngrp, Nyr); T1 <- T0; T2 <- T0; T3 <- T0; T4 <- T0
  Bmat  <- matrix(0, Ngrp, Nyr)           # biomass by group
  smat  <- matrix(0, Ngrp, Nyr)           # fishing survival by group
  qsave <- matrix(0, Nfleet * Ngrp, Nyr)  # catchabilities (stacked by fleet)
  Chat  <- matrix(0, Nfleet, Nyr)         # predicted catch weight
  Phat  <- matrix(0, Nfleet, Nyr)         # predicted catch numbers
  Mhat  <- matrix(0, Nfleet, Nyr)         # predicted mean weight of catch
  L1hat <- matrix(0, Nfleet, Nyr)         # predicted mean length of catch
  L2hat <- matrix(0, Nfleet, Nyr)         # predicted 2nd central moment
  L3hat <- matrix(0, Nfleet, Nyr)         # 3rd
  L4hat <- matrix(0, Nfleet, Nyr)         # 4th
  RB    <- rep(0, Nyr)                    # reproductive biomass
  Rrec  <- rep(0, Nyr)                    # recruitment
  B1g   <- rep(0, Ngrp)                   # year-1 biomass by group (for eq 7.5)

  # --- year-1 state: unfished equilibrium age structure --------------------
  # Iterate ages kage..Amax (no fishing, movement at end of year) and
  # accumulate T^r exactly; Amax is set high enough that l^(Amax-kage) ~ 0.
  nage <- rep(0, Ngrp); nage[1] <- R1
  tau  <- tauk
  for (j in kage:Amax) {
    T0[,1] <- T0[,1] + nage
    T1[,1] <- T1[,1] + tau   * nage
    T2[,1] <- T2[,1] + tau^2 * nage
    T3[,1] <- T3[,1] + tau^3 * nage
    T4[,1] <- T4[,1] + tau^4 * nage
    nnew <- mstay * lvec * nage
    if (Ngrp > 1)
      nnew[2:Ngrp] <- nnew[2:Ngrp] +
        (1 - mstay[1:(Ngrp-1)]) * lvec[1:(Ngrp-1)] * nage[1:(Ngrp-1)]
    nage <- nnew
    tau  <- rho * tau + phi
  }
  Rrec[1] <- R1

  # --- helper: within-year quantities for year i ---------------------------
  # (returns nothing; writes into the enclosing storage via <<-)
  do_year <- function(i) {
    Bg <- bwl * T3[,i]                                        # eq 9.2
    Bmat[,i] <<- Bg
    if (i == 1) B1g <<- Bg
    relB <- 1 - Bg / B1g                                      # eq 7.5
    qE <- matrix(0, Nfleet, Ngrp)
    for (f in 1:Nfleet) {
      qf <- Q1[f,] * exp(Q2m[f,] * relB)                      # eq 7.5
      qsave[((f-1)*Ngrp+1):(f*Ngrp), i] <<- qf
      qE[f,] <- qf * Ehat[f,i]
    }
    Zg <- qE[1,]
    if (Nfleet > 1) for (f in 2:Nfleet) Zg <- Zg + qE[f,]
    sg <- exp(-Zg)                                            # eq 7.1
    smat[,i] <<- sg
    frac <- (1 - sg) / (Zg + 1e-30)         # safe when a group is unfished
    for (f in 1:Nfleet) {
      tprop <- qE[f,] * frac                                  # eq 7.2
      S0 <- sum(tprop * T0[,i]); S1 <- sum(tprop * T1[,i])
      S2 <- sum(tprop * T2[,i]); S3 <- sum(tprop * T3[,i])
      S4 <- sum(tprop * T4[,i])
      Chat[f,i] <<- bwl * S3                                  # eq 9.3
      Phat[f,i] <<- S0
      Mhat[f,i] <<- bwl * S3 / S0                             # eq 9.4
      # non-central length moments of the catch (eqns 8.4-8.7):
      # E{(tau+eps)^r} with eps ~ N(0, sigma_tau^2)
      l1 <- S1/S0
      l2 <- S2/S0 + st2
      l3 <- S3/S0 + 3*st2*S1/S0
      l4 <- S4/S0 + 6*st2*S2/S0 + 3*st2^2
      # central moments (eqns 8.8-8.11)
      L1hat[f,i] <<- l1
      L2hat[f,i] <<- l2 - l1^2
      L3hat[f,i] <<- l3 - 3*l1*l2 + 2*l1^3
      L4hat[f,i] <<- l4 - 4*l1*l3 + 6*l1^2*l2 - 3*l1^4
    }
    RB[i] <<- sum(mat * Bg)
  }

  do_year(1)

  # --- main loop over years ------------------------------------------------
  for (i in 2:Nyr) {
    # recruitment (eq 6.1; spawning lagged kage yr, RB_1 for pre-data years)
    RBlag <- if (i - kage < 1) RB[1] else RB[i - kage]
    x <- RBlag / RB[1]
    if (gamma_sr == 0) srmult <- exp(-beta * (x - 1))                # Ricker
    else               srmult <- (1 + gamma_sr*beta*(x - 1))^(-1/gamma_sr)
    Rrec[i] <- a_sr * RBlag * srmult * exp(rec_dev[i-1])

    # delay-difference update of the moments (Theorems 3 & 4).
    # U^r_g = sum_q C(r,q) rho^q phi^(r-q) T^q_{i-1,g}
    #       = sum_j tau_{j+1}^r N_{i-1,j,g}
    P0 <- T0[,i-1]; P1 <- T1[,i-1]; P2 <- T2[,i-1]
    P3 <- T3[,i-1]; P4 <- T4[,i-1]
    U0 <- P0
    U1 <- rho*P1 + phi*P0
    U2 <- rho^2*P2 + 2*rho*phi*P1 + phi^2*P0
    U3 <- rho^3*P3 + 3*rho^2*phi*P2 + 3*rho*phi^2*P1 + phi^3*P0
    U4 <- rho^4*P4 + 4*rho^3*phi*P3 + 6*rho^2*phi^2*P2 +
          4*rho*phi^3*P1 + phi^4*P0
    stay <- mstay * lvec * smat[,i-1]              # remain in group (5.2/5.4)
    T0[,i] <- stay*U0; T1[,i] <- stay*U1; T2[,i] <- stay*U2
    T3[,i] <- stay*U3; T4[,i] <- stay*U4
    if (Ngrp > 1) {                                # influx from group g-1
      g1 <- 1:(Ngrp-1); g2 <- 2:Ngrp
      trans <- (1 - mstay[g1]) * lvec[g1] * smat[g1,i-1]
      T0[g2,i] <- T0[g2,i] + trans*U0[g1]
      T1[g2,i] <- T1[g2,i] + trans*U1[g1]
      T2[g2,i] <- T2[g2,i] + trans*U2[g1]
      T3[g2,i] <- T3[g2,i] + trans*U3[g1]
      T4[g2,i] <- T4[g2,i] + trans*U4[g1]
    }
    # recruits enter group 1 at age kage with mean length tauk
    T0[1,i] <- T0[1,i] + Rrec[i]
    T1[1,i] <- T1[1,i] + tauk   * Rrec[i]
    T2[1,i] <- T2[1,i] + tauk^2 * Rrec[i]
    T3[1,i] <- T3[1,i] + tauk^3 * Rrec[i]
    T4[1,i] <- T4[1,i] + tauk^4 * Rrec[i]

    do_year(i)
  }

  # ==========================================================================
  # Negative log posterior (eqns 2.2 / 2.5, "case 2" weighting)
  # ==========================================================================
  nll_catch  <- -sum(dnorm(log(Cobs), log(Chat), sigmaC, log=TRUE))
  # Kendall & Stuart normal-theory variances for the sample moments,
  # evaluated at the observed moments (paper, "Determining the p's").
  # lamM, lamL multiply the SDs (lam > 1 down-weights that data source).
  sdM  <- lamM    * sqrt(s2w / nsamp)
  sdL1 <- lamL[1] * sqrt(L2obs / nsamp)
  sdL2 <- lamL[2] * sqrt(2 * L2obs^2 / nsamp)
  sdL3 <- lamL[3] * sqrt(6 * L2obs^3 / nsamp)
  sdL4 <- lamL[4] * sqrt(96 * L2obs^4 / nsamp)
  nll_mw   <- -sum(dnorm(Mobs,  Mhat,  sdM,  log=TRUE))
  nll_len  <- -sum(dnorm(L1obs, L1hat, sdL1, log=TRUE)) -
               sum(dnorm(L2obs, L2hat, sdL2, log=TRUE)) -
               sum(dnorm(L3obs, L3hat, sdL3, log=TRUE)) -
               sum(dnorm(L4obs, L4hat, sdL4, log=TRUE))
  nll_eff  <- -sum(dnorm(logEdev, 0, sigmaE, log=TRUE))
  nll_rec  <- -sum(dnorm(rec_dev, 0, sigmaR, log=TRUE))

  # Bayesian priors (Table 3 of the paper; edit `data$pr*` to change)
  nll_prior <- 0
  if (UsePriors == 1) {
    nll_prior <- nll_prior - dnorm(rho,   prRho[1],  prRho[2],  log=TRUE)
    nll_prior <- nll_prior - dnorm(lsurv, prL[1],    prL[2],    log=TRUE)
    if (Ngrp > 1)
      nll_prior <- nll_prior - dnorm(1 - mstay[1], prEntry[1], prEntry[2], log=TRUE)
    nll_prior <- nll_prior - dnorm(tauk,  prTauk[1], prTauk[2], log=TRUE)
    nll_prior <- nll_prior -
      sum(dnorm(logQ1[avail==1], log(prQ1[1]), prQ1[2], log=TRUE)) -
      sum(dnorm(Q2[avail==1],    prQ2[1],      prQ2[2], log=TRUE))
  }

  # soft upper bound on group-1 mean length (paper, Table 3 footnote)
  pen <- 0
  if (Ngrp > 1) {
    mlen1 <- T1[1,] / T0[1,]
    d <- mlen1 - maxlen_g1
    h <- 0.5 * (d + sqrt(d*d + 1e-4))         # smooth hinge, max(d,0)
    pen <- lamPen * sum(h^2)
  }

  f <- nll_catch + nll_mw + nll_len + nll_eff + nll_rec + nll_prior + pen

  # --- reporting -----------------------------------------------------------
  Bavail <- rep(0, Nyr)                    # biomass available to any fishery
  gavail <- which(apply(avail, 2, max) > 0)
  for (g in gavail) Bavail <- Bavail + Bmat[g,]
  Depl <- Bavail / Bavail[1]

  ADREPORT(rho); ADREPORT(Linf); ADREPORT(tauk); ADREPORT(lsurv)
  ADREPORT(mstay); ADREPORT(a_sr); ADREPORT(beta); ADREPORT(R1)
  ADREPORT(Bavail); ADREPORT(Depl)
  Q1a <- exp(logQ1[avail==1]); Q2a <- Q2[avail==1]
  ADREPORT(Q1a); ADREPORT(Q2a)

  REPORT(f); REPORT(Chat); REPORT(Phat); REPORT(Mhat)
  REPORT(L1hat); REPORT(L2hat); REPORT(L3hat); REPORT(L4hat)
  REPORT(Bmat); REPORT(Bavail); REPORT(Depl); REPORT(RB); REPORT(Rrec)
  REPORT(smat); REPORT(qsave); REPORT(Ehat)
  REPORT(nll_catch); REPORT(nll_mw); REPORT(nll_len)
  REPORT(nll_eff); REPORT(nll_rec); REPORT(nll_prior); REPORT(pen)

  return(f)
}

# ============================================================================
# 2. Age-structured operating model (the paper's simulation example)
#    Two groups; group 1 unavailable; single fishery; Ricker SR;
#    biomass-dependent catchability.  Tracks the FULL age structure so it
#    can verify the delay-difference recursions independently.
# ============================================================================

sim_fd <- function(Nyr = 20, kage = 3, Amax = 100,
                   rho = 0.863, Linf = 14.6, sigtau = sqrt(1.8),
                   lsurv = 0.80, mstay = c(0.60, 1.0),
                   bwl = 0.03, R1 = 1000,
                   beta = 1.5, gamma_sr = 0,
                   Q1 = 0.0036, Q2 = 1.3,
                   Etrue = NULL, sigR = 0.3, sigE = 0.3,
                   nsamp = 500) {
  Ngrp <- length(mstay)
  ages <- kage:Amax; nage_n <- length(ages)
  tauj <- Linf * (1 - rho^ages)            # vB through origin; tau_k ~ 5.2
  wj   <- bwl * tauj^3
  if (is.null(Etrue))
    Etrue <- c(seq(10, 50, length=12), seq(48, 26, length=8))[1:Nyr]

  # unfished equilibrium age structure (movement at end of year, no fishing)
  N <- matrix(0, nage_n, Ngrp)
  nvec <- c(R1, rep(0, Ngrp-1))
  for (j in 1:nage_n) {
    N[j,] <- nvec
    nnew <- mstay * lsurv * nvec
    if (Ngrp > 1)
      nnew[2:Ngrp] <- nnew[2:Ngrp] +
        (1 - mstay[1:(Ngrp-1)]) * lsurv * nvec[1:(Ngrp-1)]
    nvec <- nnew
  }
  RB1 <- sum(wj * N[,Ngrp])                # group G = mature (paper, Step 10)
  a_sr <- R1 / RB1                         # virgin equilibrium: R1 = a*RB1

  out <- list(B=matrix(0,Ngrp,Nyr), Ctrue=rep(0,Nyr), Mw_true=rep(0,Nyr),
              L_true=matrix(0,4,Nyr), q=rep(0,Nyr), s=matrix(0,Ngrp,Nyr),
              RB=rep(0,Nyr), R=rep(0,Nyr), Etrue=Etrue,
              Cobs=rep(0,Nyr), Eobs=rep(0,Nyr), Mobs=rep(0,Nyr),
              L1obs=rep(0,Nyr), L2obs=rep(0,Nyr), L3obs=rep(0,Nyr),
              L4obs=rep(0,Nyr), s2w=rep(0,Nyr),
              rec_dev=rep(0,Nyr), Edev=rep(0,Nyr))
  out$rec_dev <- rnorm(Nyr, 0, sigR); out$rec_dev[1] <- 0
  out$Edev    <- rnorm(Nyr, 0, sigE)
  out$R[1] <- R1
  B1g <- colSums(wj * N)

  for (i in 1:Nyr) {
    Bg <- colSums(wj * N)
    out$B[,i] <- Bg
    qg <- Q1 * exp(Q2 * (1 - Bg[Ngrp]/B1g[Ngrp]))     # available group only
    qvec <- c(rep(0, Ngrp-1), qg)
    sg <- exp(-qvec * Etrue[i])
    out$q[i] <- qg; out$s[,i] <- sg
    tg <- 1 - sg                                       # single fishery
    catchN <- sweep(N, 2, tg, "*")                     # numbers caught by age/grp
    P <- sum(catchN)
    out$Ctrue[i]   <- sum(wj * rowSums(catchN))
    out$Mw_true[i] <- out$Ctrue[i] / P
    # true length moments of the catch (mixture over ages + N(0,sigtau^2))
    cn <- rowSums(catchN)
    l1 <- sum(cn*tauj)/P
    l2 <- sum(cn*tauj^2)/P + sigtau^2
    l3 <- sum(cn*tauj^3)/P + 3*sigtau^2*sum(cn*tauj)/P
    l4 <- sum(cn*tauj^4)/P + 6*sigtau^2*sum(cn*tauj^2)/P + 3*sigtau^4
    out$L_true[,i] <- c(l1, l2 - l1^2, l3 - 3*l1*l2 + 2*l1^3,
                        l4 - 4*l1*l3 + 6*l1^2*l2 - 3*l1^4)
    out$RB[i] <- Bg[Ngrp]

    # observations
    out$Cobs[i] <- out$Ctrue[i]                        # catch ~ exact (p0 big)
    out$Eobs[i] <- Etrue[i] * exp(out$Edev[i])         # 30% effort error
    idx <- sample(seq_along(cn), nsamp, replace=TRUE, prob=cn/P)
    x   <- tauj[idx] + rnorm(nsamp, 0, sigtau)         # sampled lengths
    w   <- bwl * x^3                                   # sampled weights
    out$Mobs[i]  <- mean(w);      out$s2w[i] <- var(w)
    out$L1obs[i] <- mean(x)
    out$L2obs[i] <- mean((x - mean(x))^2)
    out$L3obs[i] <- mean((x - mean(x))^3)
    out$L4obs[i] <- mean((x - mean(x))^4)

    # update population: fishing survival, natural mortality, movement,
    # then recruitment into group 1 at age kage
    if (i < Nyr) {
      Ns <- sweep(N, 2, sg * lsurv, "*")
      Nn <- matrix(0, nage_n, Ngrp)
      Nn[2:nage_n,] <- sweep(Ns[1:(nage_n-1),], 2, mstay, "*")
      if (Ngrp > 1)
        Nn[2:nage_n, 2:Ngrp] <- Nn[2:nage_n, 2:Ngrp] +
          sweep(Ns[1:(nage_n-1), 1:(Ngrp-1), drop=FALSE], 2,
                (1 - mstay[1:(Ngrp-1)]), "*")
      RBlag <- if (i + 1 - kage < 1) out$RB[1] else out$RB[i + 1 - kage]
      xr <- RBlag / out$RB[1]
      srm <- if (gamma_sr == 0) exp(-beta*(xr - 1))
             else (1 + gamma_sr*beta*(xr - 1))^(-1/gamma_sr)
      out$R[i+1] <- a_sr * RBlag * srm * exp(out$rec_dev[i+1])
      Nn[1,1] <- out$R[i+1]
      N <- Nn
    }
  }
  out$pars <- list(rho=rho, Linf=Linf, tauk=tauj[1], sigtau=sigtau,
                   lsurv=lsurv, mstay=mstay, bwl=bwl, R1=R1, a_sr=a_sr,
                   beta=beta, gamma_sr=gamma_sr, Q1=Q1, Q2=Q2,
                   kage=kage, Amax=Amax, sigR=sigR, sigE=sigE, nsamp=nsamp)
  out
}

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
obj0 <- MakeADFun(f_dd, true_parameters, map = map_all, silent = TRUE)
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
#   MakeADFun(f_dd, parameters, map=map, random=c("logEdev","rec_dev"), ...)
# ----------------------------------------------------------------------------
model <- MakeADFun(f_dd, parameters, map = map,
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
pdf("fournier_doonan_RTMB_fit.pdf", width = 10, height = 7)
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
cat("\nPlots written to fournier_doonan_RTMB_fit.pdf\n")
