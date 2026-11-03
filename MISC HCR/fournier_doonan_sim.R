# ============================================================================
# fournier_doonan_sim.R -- age-structured operating model for testing the
# Fournier & Doonan (1987) delay-difference model (R Inserts/DelayDiff.R).
# Used by fournier_doonan_delaydiff_RTMB.R and test_Run_DelayDiff.R.
# ============================================================================
# Age-structured operating model (the paper's simulation example)
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
                   nsamp = 500, lobins = NULL) {
  # lobins: optional length-bin edges; if given, the sampled lengths are also
  # returned as binned counts (out$Lcomp, Nyr x bins; ends are plus groups)
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
  if (!is.null(lobins)) out$Lcomp <- matrix(0, Nyr, length(lobins) - 1)
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
    if (!is.null(lobins))
      out$Lcomp[i,] <- tabulate(pmin(pmax(findInterval(x, lobins), 1),
                                     length(lobins) - 1), length(lobins) - 1)
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

