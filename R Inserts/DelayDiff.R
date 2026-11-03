# ============================================================================
# DelayDiff.R -- Fournier & Doonan (1987) generalized delay-difference model
# as a ratpackR estimation method (Ass$Type "Tier_DD").
#
#   Fournier, D.A. and Doonan, I.J. (1987). A length-based stock assessment
#   method utilizing a generalized delay-difference model.
#   Can. J. Fish. Aquat. Sci. 44: 422-437.
#
# Contents
#   dd_advance      moment update between years (Theorems 3 & 4)
#   f_dd            RTMB objective, f_dd(parms, data); use MakeADFun(cmb(f_dd,data),...)
#   DD_comp_moments moments of a catch length composition
#   DD_project      deterministic projection of a fitted model under an HCR
#   Run_DelayDiff   the ratpackR assessment method (called from Run_Assessment)
#
# The demo / verification against an age-structured operating model is in
# MISC HCR/fournier_doonan_delaydiff_RTMB.R.
#
# Model summary
# -------------
# The population is divided into G "groups" (Deriso's partial-recruitment
# device).  Recruits (age kage) enter group 1; each year a fish in group g
# moves to group g+1 with probability (1 - m_g) at the END of the year
# ("scheme 2", eqns 5.1-5.4).  The last group retains its fish (m_G = 1).
# Fisheries operate instantaneously at the START of the year; natural
# mortality (survival l) operates through the year.
#
# Mean length at age lies on a von Bertalanffy curve (eq 10.1):
#     tau_{j+1} = rho * tau_j + (1-rho) * Linf
# and mean weight at age is w_j = bwl * tau_j^3 (eq 9.1, v = 3).
# The moments T^r_{ig} = sum_j tau_j^r N_{ijg}, r = 0..4, satisfy a closed
# first-order system of difference equations, so no age structure is needed.
#     biomass         B_ig  = bwl * T3_ig                        (eq  9.2)
#     catch weight    C_fi  = sum_g t_fig B_ig                   (eq  9.3)
#     mean weight     M_fi  = C_fi / (sum_g t_fig T0_ig)         (eq  9.4)
#     length moments  from T0..T4 + within-age N(0, sigma_tau^2) noise
#                     (eqns 8.4-8.11)
#     q_fig = Q1_fg * exp( Q2_fg * (1 - B_ig/B_1g) )             (eq  7.5)
#     s_ig  = exp( -sum_f q_fig E_fi )                           (eq  7.1)
#     t_fig = (q_fig E_fi / Z_ig) * (1 - s_ig)                   (eq  7.2)
#     R_i = a * RB * (1 + gamma*beta*(RB/RB_1 - 1))^(-1/gamma) * exp(eps_i)
#     (eq 6.1; gamma -> 0 Ricker, gamma = 1 Beverton-Holt; spawning lagged
#     kage years, RB_1 used for pre-data years)
#
# Missing data: any observation may be NA and is then left out of the
# likelihood.  Effort that is NA (no CPUE index that year) must be replaced
# by a placeholder before the fit and its effort penalty switched off with
# Emask = 0; effective effort is then a free parameter determined by the
# catch.  Year-1 state is unfished equilibrium.
#
# SRvirgin = 1 ties the SR productivity to the unfished state (a = R1/RB_1,
# so year 1 is an equilibrium of the SR curve and loga must be mapped out);
# SRvirgin = 0 estimates a freely, as in the paper.
# ============================================================================

# --- moment update from year i-1 to year i (Theorems 3 & 4) -----------------
# P: list(T0..T4) for year i-1; stay/trans: within-group survival and
# group-to-group transfer; Rnew: recruits entering group 1 at length tauk.
dd_advance <- function(P, stay, trans, rho, phi, Rnew, tauk)
{
  Ngrp <- length(P[[1]])
  P0 <- P[[1]]; P1 <- P[[2]]; P2 <- P[[3]]; P3 <- P[[4]]; P4 <- P[[5]]
  # U^r_g = sum_q C(r,q) rho^q phi^(r-q) T^q_{i-1,g} = sum_j tau_{j+1}^r N_{i-1,j,g}
  U <- list(P0,
            rho*P1 + phi*P0,
            rho^2*P2 + 2*rho*phi*P1 + phi^2*P0,
            rho^3*P3 + 3*rho^2*phi*P2 + 3*rho*phi^2*P1 + phi^3*P0,
            rho^4*P4 + 4*rho^3*phi*P3 + 6*rho^2*phi^2*P2 + 4*rho*phi^3*P1 + phi^4*P0)
  Tn <- vector("list", 5)
  for (r in 1:5) {
    Tr <- stay * U[[r]]                                  # remain in group (5.2/5.4)
    if (Ngrp > 1)                                        # influx from group g-1
      Tr[2:Ngrp] <- Tr[2:Ngrp] + trans * U[[r]][1:(Ngrp-1)]
    Tr[1] <- Tr[1] + tauk^(r-1) * Rnew                   # recruits at length tauk
    Tn[[r]] <- Tr
  }
  Tn
}

# --- SR multiplier (eq 6.1) --------------------------------------------------
dd_srmult <- function(x, beta, gamma_sr)
{
  if (gamma_sr == 0) exp(-beta * (x - 1))                # Ricker
  else (1 + gamma_sr*beta*(x - 1))^(-1/gamma_sr)
}

# ============================================================================
# RTMB objective function
# ============================================================================
f_dd <- function(parms, data) {
  getAll(data, parms, warn = FALSE)
  # masks are built from `data` directly: objects created inside the taped
  # function can become AD types, and comparisons on those fail
  okE <- if (is.null(data$Emask)) rep(TRUE, length(data$Cobs)) else as.vector(data$Emask == 1)
  okC <- as.vector(!is.na(data$Cobs) & data$Cobs > 0)
  okM <- as.vector(!is.na(data$Mobs) & !is.na(data$nsamp) & data$nsamp > 0)
  okL <- as.vector(!is.na(data$L1obs) & !is.na(data$nsamp) & data$nsamp > 0)
  if (is.null(data$SRvirgin)) SRvirgin <- 0
  if (is.null(data$lamRecSum)) lamRecSum <- 0

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
      S0 <- S0 + 1e-30                  # no 0/0 (and NaN gradients) when unfished
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
  if (SRvirgin == 1) a_sr <- R1 / RB[1]   # year 1 is an equilibrium of the SR curve

  # --- main loop over years ------------------------------------------------
  stay  <- mstay * lvec
  trans <- if (Ngrp > 1) (1 - mstay[1:(Ngrp-1)]) * lvec[1:(Ngrp-1)] else NULL
  for (i in 2:Nyr) {
    # recruitment (eq 6.1; spawning lagged kage yr, RB_1 for pre-data years)
    RBlag <- if (i - kage < 1) RB[1] else RB[i - kage]
    Rrec[i] <- a_sr * RBlag * dd_srmult(RBlag / RB[1], beta, gamma_sr) * exp(rec_dev[i-1])

    s_prev <- smat[,i-1]
    Tn <- dd_advance(list(T0[,i-1], T1[,i-1], T2[,i-1], T3[,i-1], T4[,i-1]),
                     stay * s_prev,
                     if (Ngrp > 1) trans * s_prev[1:(Ngrp-1)] else NULL,
                     rho, phi, Rrec[i], tauk)
    T0[,i] <- Tn[[1]]; T1[,i] <- Tn[[2]]; T2[,i] <- Tn[[3]]
    T3[,i] <- Tn[[4]]; T4[,i] <- Tn[[5]]

    do_year(i)
  }

  # ==========================================================================
  # Negative log posterior (eqns 2.2 / 2.5, "case 2" weighting)
  # NA observations (and zero catches) are left out.
  # ==========================================================================
  nll_catch <- -sum(dnorm(log(Cobs[okC]), log(Chat[okC]), sigmaC, log=TRUE))
  # Kendall & Stuart normal-theory variances for the sample moments,
  # evaluated at the observed moments (paper, "Determining the p's").
  # lamM, lamL multiply the SDs (lam > 1 down-weights that data source;
  # lam <= 0 drops it).
  nll_mw <- 0
  if (lamM > 0 && any(okM)) {
    sdM <- lamM * sqrt(s2w[okM] / nsamp[okM])
    nll_mw <- -sum(dnorm(Mobs[okM], Mhat[okM], sdM, log=TRUE))
  }
  nll_len <- 0
  if (any(okL)) {
    L2o <- L2obs[okL]; n <- nsamp[okL]
    if (lamL[1] > 0) nll_len <- nll_len -
      sum(dnorm(L1obs[okL], L1hat[okL], lamL[1]*sqrt(L2o/n), log=TRUE))
    if (lamL[2] > 0) nll_len <- nll_len -
      sum(dnorm(L2obs[okL], L2hat[okL], lamL[2]*sqrt(2*L2o^2/n), log=TRUE))
    if (lamL[3] > 0) nll_len <- nll_len -
      sum(dnorm(L3obs[okL], L3hat[okL], lamL[3]*sqrt(6*L2o^3/n), log=TRUE))
    if (lamL[4] > 0) nll_len <- nll_len -
      sum(dnorm(L4obs[okL], L4hat[okL], lamL[4]*sqrt(96*L2o^4/n), log=TRUE))
  }
  nll_eff <- -sum(dnorm(logEdev[okE], 0, sigmaE, log=TRUE))
  nll_rec <- -sum(dnorm(rec_dev, 0, sigmaR, log=TRUE))
  # optional soft sum-to-zero constraint on the deviations (as in SS), so a
  # sustained decline cannot be explained by recruitment alone
  if (lamRecSum > 0) nll_rec <- nll_rec + lamRecSum * sum(rec_dev)^2

  # Bayesian priors (Table 3 of the paper; a prior with SD <= 0 is skipped)
  nll_prior <- 0
  addprior <- function(x, pr) if (pr[2] > 0) -sum(dnorm(x, pr[1], pr[2], log=TRUE)) else 0
  if (UsePriors == 1) {
    nll_prior <- nll_prior + addprior(rho, prRho) + addprior(lsurv, prL) +
                 addprior(tauk, prTauk)
    if (Ngrp > 1) nll_prior <- nll_prior + addprior(1 - mstay[1], prEntry)
    nll_prior <- nll_prior +
      addprior(logQ1[avail==1], c(log(prQ1[1]), prQ1[2])) +
      addprior(Q2[avail==1], prQ2)
  }

  # soft upper bound on group-1 mean length (paper, Table 3 footnote)
  pen <- 0
  if (Ngrp > 1 && lamPen > 0) {
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
  REPORT(smat); REPORT(qsave); REPORT(Ehat); REPORT(B1g)
  REPORT(T0); REPORT(T1); REPORT(T2); REPORT(T3); REPORT(T4)
  REPORT(rho); REPORT(phi); REPORT(Linf); REPORT(tauk); REPORT(lsurv); REPORT(mstay)
  REPORT(a_sr); REPORT(beta); REPORT(R1); REPORT(Q1); REPORT(Q2m)
  REPORT(nll_catch); REPORT(nll_mw); REPORT(nll_len)
  REPORT(nll_eff); REPORT(nll_rec); REPORT(nll_prior); REPORT(pen)

  return(f)
}

# ============================================================================
# Moments of a catch length composition
# comp: counts over Nlen bins (1 sex) or 2*Nlen (female then male, SS order)
# lo:   lower bin edges (length Nlen+1); bwl: w = bwl*len^3.
# Sheppard's corrections remove the extra spread from binning when the bins
# are of equal width (mu2 = m2 - h^2/12, mu4 = m4 - h^2 m2/2 + 7h^4/240).
# ============================================================================
DD_comp_moments <- function(comp, lo, bwl, Nsex)
{
  Nlen <- length(lo) - 1
  mids <- lo[1:Nlen] + diff(lo)/2
  clen <- colSums(matrix(comp, nrow=Nsex, byrow=TRUE))   # combined sexes
  n    <- sum(clen)
  L1 <- sum(clen*mids)/n
  L2 <- sum(clen*(mids-L1)^2)/n
  L3 <- sum(clen*(mids-L1)^3)/n
  L4 <- sum(clen*(mids-L1)^4)/n
  h <- diff(lo)
  if (max(h) - min(h) < 1e-8) {
    h <- h[1]
    L4 <- L4 - h^2*L2/2 + 7*h^4/240
    L2 <- L2 - h^2/12
  }
  w   <- bwl * mids^3
  Mw  <- sum(clen*w)/n
  s2w <- sum(clen*(w-Mw)^2)/n
  list(L1=L1, L2=L2, L3=L3, L4=L4, Mw=Mw, s2w=s2w, n=n)
}

# ============================================================================
# Deterministic projection of a fitted model (single fishery, rec_dev = 0).
# Rep: model$report() of the fit; data: the fit's data list.
# hcr(Depl, Bavail) returns the catch for a year given that year's
# start-of-year availability.  Returns catches and trajectories for Nproj
# years after the last data year.
# ============================================================================
DD_project <- function(Rep, data, hcr, Nproj=50)
{
  Nyr  <- ncol(data$Cobs)
  Ngrp <- ncol(data$avail)
  kage <- data$kage
  stay  <- Rep$mstay * Rep$lsurv
  trans <- if (Ngrp > 1) (1 - Rep$mstay[1:(Ngrp-1)]) * Rep$lsurv else NULL
  Q1 <- Rep$Q1[1,]; Q2 <- Rep$Q2m[1,]
  gavail <- which(data$avail[1,] > 0)

  Tcur <- list(Rep$T0[,Nyr], Rep$T1[,Nyr], Rep$T2[,Nyr], Rep$T3[,Nyr], Rep$T4[,Nyr])
  s_prev <- Rep$smat[,Nyr]
  RB <- c(Rep$RB, rep(NA, Nproj))
  Bav0 <- Rep$Bavail[1]
  out <- list(Catch=rep(0,Nproj), Bavail=rep(0,Nproj), Depl=rep(0,Nproj),
              RB=rep(0,Nproj), Rrec=rep(0,Nproj), E=rep(0,Nproj))

  for (t in 1:Nproj) {
    i <- Nyr + t
    RBlag <- if (i - kage < 1) RB[1] else RB[i - kage]
    Rnew <- Rep$a_sr * RBlag * dd_srmult(RBlag / RB[1], Rep$beta, data$gamma_sr)
    Tcur <- dd_advance(Tcur, stay * s_prev,
                       if (Ngrp > 1) trans * s_prev[1:(Ngrp-1)] else NULL,
                       Rep$rho, Rep$phi, Rnew, Rep$tauk)
    Bg <- data$bwl * Tcur[[4]]
    Bav <- sum(Bg[gavail])
    RB[i] <- sum(data$mat * Bg)
    Dep <- Bav / Bav0
    Ctarget <- max(0, hcr(Dep, Bav))

    # effort giving the target catch (instantaneous fishery at start of year)
    q <- Q1 * exp(Q2 * (1 - Bg / Rep$B1g))
    catchE <- function(E) sum((1 - exp(-q*E)) * Bg)
    E <- 0
    if (Ctarget > 0) {
      Ctarget <- min(Ctarget, 0.95 * sum(Bg[q > 0]))
      Emax <- 1
      while (catchE(Emax) < Ctarget) Emax <- Emax * 10
      E <- uniroot(function(E) catchE(E) - Ctarget, c(0, Emax), tol=1e-10)$root
    }
    s_prev <- exp(-q * E)
    out$Catch[t] <- Ctarget; out$Bavail[t] <- Bav; out$Depl[t] <- Dep
    out$RB[t] <- RB[i]; out$Rrec[t] <- Rnew; out$E[t] <- E
  }
  out
}

# ============================================================================
# The ratpackR assessment method ("Tier_DD")
# Options come from the #Tier_DD: block of the .EM file (ReadIn.R).
# ============================================================================
Run_DelayDiff <- function(Isim, Istock, Year, Plot=F)
{
  cat("Running delay-difference (Fournier-Doonan) EM:", Isim, Istock, Year, "\n")
  DD <- Stock[[Istock]]$Ass$DD
  YrOffset <- Stock[[Istock]]$YrOffset

  # weight-length with the cubic exponent the model needs: refit a with b=3
  # over the length bins (log scale), from the EM's weight-length if present
  lo   <- Stock[[Istock]]$LoLenBin
  Nlen <- length(lo) - 1
  mids <- lo[1:Nlen] + diff(lo)/2
  WLa <- Stock[[Istock]]$Ass$SS_WtLen_a; WLb <- Stock[[Istock]]$Ass$SS_WtLen_b
  if (is.null(WLa)) { WLa <- Stock[[Istock]]$WtLen_a; WLb <- Stock[[Istock]]$WtLen_b }
  bwl <- exp(mean(log(WLa[1]) + (WLb[1] - 3)*log(mids)))

  # 1. catch (single aggregated fishery)
  Catch <- rep(0, Year)
  for (Iyear in 1:Year) Catch[Iyear] <- sum(Stock[[Istock]]$Data$Catches[,,Iyear], na.rm=T)
  Catch[Catch < 1e-6*max(Catch)] <- 0                 # "zero" catches from the projection

  # 2. effort = catch / CPUE for the chosen index (cf. Run_Tier4b);
  #    negative years are data not yet available
  IndexVl <- rep(NA, Year)
  IndexData <- Stock[[Istock]]$Data$IndexData.Used
  rows <- which(IndexData[DD$Cpue_Area,,3] == DD$Cpue_Index)
  for (r in rows) {
    TheYear <- IndexData[DD$Cpue_Area,r,1] - YrOffset
    if (TheYear >= 1 && TheYear <= Year && IndexData[DD$Cpue_Area,r,4] > 0)
      IndexVl[TheYear] <- IndexData[DD$Cpue_Area,r,4]
  }
  Eobs <- Catch / IndexVl
  Emask <- as.numeric(!is.na(Eobs) & Catch > 0)
  # years without an index: placeholder effort, effective effort set by the
  # catch; zero-catch years: (almost) no effort, deviation fixed
  Egm <- exp(mean(log(Eobs[Emask == 1])))
  Eobs[is.na(Eobs)] <- Egm
  Eobs[Catch <= 0] <- 1.0e-8 * Egm

  # 3. length-comp moments (Part: 0 = total catch, 2 = retained)
  Nsex <- Stock[[Istock]]$Nsex
  L1 <- L2 <- L3 <- L4 <- Mobs <- s2w <- nsamp <- rep(NA, Year)
  LD <- Stock[[Istock]]$Data$LengthData.Used
  rows <- which(LD[,1] == DD$Len_Area & LD[,4] == DD$Len_Fleet & LD[,6] == DD$Len_Part & LD[,2] > 0)
  for (r in rows) {
    TheYear <- LD[r,2] - YrOffset
    # comps in zero-catch years are generated from an almost empty catch
    if (TheYear >= 1 && TheYear <= Year && LD[r,7] > 0 && Catch[TheYear] > 0) {
      mm <- DD_comp_moments(LD[r, 7+(1:(Nsex*Nlen))], lo, bwl, Nsex)
      L1[TheYear] <- mm$L1; L2[TheYear] <- mm$L2
      L3[TheYear] <- mm$L3; L4[TheYear] <- mm$L4
      Mobs[TheYear] <- mm$Mw; s2w[TheYear] <- mm$s2w
      nsamp[TheYear] <- min(LD[r,7], DD$MaxNsamp)       # stated sample size
    }
  }

  # 4. model data (2 groups: pre-fishable + fishable, as in the paper)
  avail <- matrix(c(0,1), 1, 2)
  data <- list(
    Cobs  = matrix(Catch, 1, Year),  Eobs  = matrix(Eobs, 1, Year),
    Emask = matrix(Emask, 1, Year),
    Mobs  = matrix(Mobs, 1, Year),   s2w   = matrix(s2w, 1, Year),
    L1obs = matrix(L1, 1, Year),     L2obs = matrix(L2, 1, Year),
    L3obs = matrix(L3, 1, Year),     L4obs = matrix(L4, 1, Year),
    nsamp = matrix(nsamp, 1, Year),
    avail = avail, mat = c(0,1),
    kage = DD$kage, Amax = DD$Amax, gamma_sr = DD$gamma_sr, bwl = bwl,
    SRvirgin = 1, lamRecSum = DD$lamRecSum,
    sigmaC = DD$sigmaC, sigmaE = DD$sigmaE, sigmaR = DD$sigmaR,
    lamM = DD$lamM, lamL = DD$lamL, UsePriors = 1,
    prRho = DD$Rho, prL = DD$Surv, prEntry = DD$Entry, prTauk = DD$Tauk,
    prQ1 = c(NA, DD$Q1sd), prQ2 = DD$Q2,
    maxlen_g1 = DD$MaxLen_g1, lamPen = DD$lamPen)

  # 5. initial values: prior means; virgin fishable biomass B0_init_mult x
  #    the largest catch, and Q1 giving that harvest rate in the first index
  #    year.  Q1 is in index units; Q1sd > 0 puts a lognormal prior on it
  #    centred on this guess (i.e. on that harvest rate), otherwise none.
  #    The likelihood can have a local optimum at a very large B0 (fishing
  #    then has no effect), so the fit is started from three B0 scales
  #    (x1/3, x1, x3) and the best objective is kept.
  pr <- dd_per_recruit(DD$Rho[1], DD$Linf_init, DD$Tauk[1], DD$Surv[1],
                       c(1 - DD$Entry[1], 1), bwl, DD$kage, DD$Amax)
  Iyr <- which(Emask == 1)[1]
  Q1_guess <- function(B0) -log(1 - min(0.5, Catch[Iyr]/B0)) / Eobs[Iyr]
  data$prQ1[1] <- Q1_guess(DD$B0_init_mult * max(Catch))
  make_pars <- function(B0_init)
    list(
      logR1 = log(B0_init / pr$B[2]), loga = log(1/pr$B[2]), logbeta = log(DD$beta_init),
      logit_rho = qlogis(DD$Rho[1]), logLinf = log(DD$Linf_init), tauk = DD$Tauk[1],
      logit_l = qlogis(DD$Surv[1]), logit_m = qlogis(1 - DD$Entry[1]),
      logQ1 = matrix(log(Q1_guess(B0_init)), 1, 2), Q2 = matrix(DD$Q2[1], 1, 2),
      log_sigma_tau = log(DD$Sigtau),
      logEdev = matrix(0, 1, Year),
      rec_dev = rep(0, Year - 1))
  Edev_map <- seq_len(Year); Edev_map[Catch <= 0] <- NA
  map <- list(loga = factor(NA),                       # SRvirgin = 1
              logQ1 = factor(c(NA, 1)),
              Q2 = factor(c(NA, if (DD$EstQ2 == "Yes") 1 else NA)),
              log_sigma_tau = factor(NA),              # within-age SD from ageing
              logEdev = factor(Edev_map))
  if (DD$EstBeta != "Yes") map$logbeta <- factor(NA)
  if (DD$EstLinf != "Yes") map$logLinf <- factor(NA)
  # recruitment deviations only where the length data can inform them
  rdmap <- rep(NA, Year - 1)
  okyr <- which(!is.na(L1))
  if (length(okyr) > 0) {
    first <- max(1, min(okyr) - DD$RecDevLead - 1)
    if (first <= Year - 1) rdmap[first:(Year-1)] <- first:(Year-1)
  }
  map$rec_dev <- factor(rdmap)

  best <- NULL
  for (B0mult in DD$B0_init_mult * c(1/3, 1, 3)) {
    parameters <- make_pars(B0mult * max(Catch))
    # phase 1: effort deviations only, so the starting point fits the catches
    map1 <- lapply(parameters, function(x) factor(rep(NA, length(x))))
    map1$logEdev <- map$logEdev
    model1 <- MakeADFun(cmb(f_dd, data), parameters, map=map1, silent=TRUE)
    fit1 <- try(nlminb(model1$par, model1$fn, model1$gr,
                       control=list(eval.max=10000, iter.max=1000)), silent=TRUE)
    if (!inherits(fit1, "try-error"))
      parameters$logEdev[] <- model1$env$parList(model1$env$last.par.best)$logEdev
    # phase 2: everything
    model <- MakeADFun(cmb(f_dd, data), parameters, map=map, silent=TRUE)
    fit <- try(nlminb(model$par, model$fn, model$gr,
                      control=list(eval.max=10000, iter.max=1000)), silent=TRUE)
    if (inherits(fit, "try-error")) next
    for (i in 1:5) {
      fit2 <- try(nlminb(model$env$last.par.best, model$fn, model$gr,
                         control=list(eval.max=10000, iter.max=1000)), silent=TRUE)
      if (!inherits(fit2, "try-error")) fit <- fit2
    }
    obj <- model$fn(model$env$last.par.best)
    if (is.finite(obj) && (is.null(best) || obj < best$obj))
      best <- list(obj=obj, model=model, fit=fit, parameters=parameters, B0mult=B0mult)
  }
  if (is.null(best)) stop("Tier_DD: all fits failed (Isim ", Isim, ", Year ", Year, ")")
  model <- best$model; fit <- best$fit; parameters <- best$parameters
  Report <- model$report(model$env$last.par.best)
  maxgrad <- max(abs(model$gr(model$env$last.par.best)))
  if (maxgrad > 0.01) cat("Tier_DD: max gradient", maxgrad, fit$message, "\n")
  DD.Last.Fit <<- list(data=data, parameters=parameters, map=map, model=model,
                       fit=fit, Report=Report)    # for diagnostics only

  # 6. store estimates (ratpack convention, cf. Run_Tier4a)
  Nhist <- Stock[[Istock]]$Nhist
  Stock[[Istock]]$Ass$SSB.estimates[Isim, Year-Nhist+1, 1, 1:Year]  <<- Report$RB
  Stock[[Istock]]$Ass$Depl.estimates[Isim, Year-Nhist+1, 1, 1:Year] <<- Report$Depl*100

  if (Plot) {
    par(mfrow=c(2,2))
    plot(1:Year, Catch, pch=16, xlab="Year", ylab="Catch"); lines(1:Year, Report$Chat[1,], lwd=2)
    plot(1:Year, L1, pch=16, xlab="Year", ylab="Mean length"); lines(1:Year, Report$L1hat[1,], lwd=2)
    plot(1:Year, Report$Depl, type="l", lwd=2, xlab="Year", ylab="Depletion", ylim=c(0,1.1))
    plot(1:Year, Report$Rrec, type="l", lwd=2, xlab="Year", ylab="Recruitment")
  }

  # 7. HCR -- PLACEHOLDER (DECIDE WITH PAUL): linear rule on depletion of
  #    fishable biomass applied to a target harvest fraction, run through the
  #    fitted model so the 50-year RBC vector has feedback, as Tier_4a does.
  #    Alternatives: F&D's effort giving maximum long-term yield, or a
  #    model-based F_MSY proxy.
  hcr <- function(Dep, Bav)
    DD$Htarg * max(0, min(1, (Dep - DD$Dlim)/(DD$Dtarg - DD$Dlim))) * Bav
  Proj <- DD_project(Report, data, hcr, Nproj=50)
  return(Proj$Catch)
}

# --- per-recruit unfished biomass and numbers by group (for initial values) -
dd_per_recruit <- function(rho, Linf, tauk, l, m, b, kage, Amax)
{
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
