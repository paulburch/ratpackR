# ============================================================================
# DelayDiff_EM_draft.R  --  DRAFT, NOT YET WIRED IN OR TESTED
#
# Fournier & Doonan (1987) generalized delay-difference model as a ratpackR
# estimation method ("Tier_DD"), modeled on Run_Tier4a in R Inserts/Assessment.R.
# The model itself is MISC HCR/fournier_doonan_delaydiff_RTMB.R (f_dd + a
# simulation self-test; source only the f_dd section, or split the file,
# when wiring in).
#
# Status (3 Nov 2026): the model is verified against an age-structured
# operating model to ~1e-9 and recovers parameters from simulated data.
# This wrapper maps ratpackR's generated data onto the model's inputs and
# sketches the TAC step.  It has NOT been run inside ratpackR.
#
# --- What ratpackR provides vs what the model needs -------------------------
#   model input                       ratpackR source
#   catch weight C_fi                 Stock[[Istock]]$Data$Catches[,,Iyear]
#   fishing effort E_fi               derived: Catch / CPUE index
#                                     (IndexData.Used[Iarea,,c(1,3,4,5)]);
#                                     F&D treat estimated effort as lognormal
#                                     around effective effort, so index error
#                                     maps directly onto sigmaE
#   mean weight, s2w of catch         length comps (LengthData.Used row:
#   mean length + central moments     area, yr+off, 7, fleet, sexcode, part,
#   2-4, sample size                  Nsamp, bins...) x bin mids from
#                                     Stock[[Istock]]$LoLenBin and
#                                     Stock[[Istock]]$WtLen
#   bwl (w = b*len^3)                 Stock[[Istock]]$WtLen_a (check WtLen_b
#                                     ~= 3; F&D require the cubic exponent)
#   priors, kage, groups, HCR pars    new Ass$DD block in the .EM file
#                                     (ReadIn.R addition, see TODOs)
#
# --- Required changes before this runs --------------------------------------
# 1. f_dd assumes complete data; ratpack years can lack an index or length
#    sample.  Add NA masks to each likelihood term in f_dd (skip NA cells),
#    and carry effort forward (or estimate freely with a diffuse penalty)
#    in no-index years.
# 2. f_dd reads `data` from the calling/global environment.  Either keep the
#    `data <<- ...` below (works, but clobbers any global `data`) or change
#    f_dd to f_dd(parms, data) and use cmb() exactly as Run_Tier4a does.
# 3. Dispatch: add to Run_Assessment in R Inserts/Assessment.R:
#      if (Stock[[Istock]]$Ass$Type=="Tier_DD") TACs <- Run_DelayDiff(Isim,Istock,Year)
#    and source this file (or move Run_DelayDiff into Assessment.R on the
#    branch; keep the diff against upstream small).
# 4. ReadIn.R: parse the Ass$DD options from the .EM file the same way the
#    Tier4a block is read.
# 5. HCR (DECIDE WITH PAUL): below is a placeholder linear 20:35:48-style
#    rule on estimated fishable-biomass depletion applied to a target
#    harvest fraction.  Alternatives: F&D's own approach (effort giving
#    maximum long-term yield from the fitted model), or projecting the
#    fitted model under candidate TACs as Tier4a's f2 does internally.
# 6. MSE test plan: pick a single-area, single-sex test stock from
#    Inputs CSIRO; run Estimation.test / deterministic data first
#    (Deter.* switches) and check the EM tracks the OM (Check.Setup.R
#    style) before stochastic replicates; compare against Tier_4a on the
#    same OM.
# ============================================================================

# --- helper: moments of a catch length comp ---------------------------------
# comp: counts over Nlen bins (1 sex) or 2*Nlen (female then male, SS order)
# mids: bin midpoints; WtLen: Nsex x Nlen weight-at-length matrix
DD_comp_moments <- function(comp, mids, WtLen, Nsex, Nlen)
{
  cmat <- matrix(comp, nrow=Nsex, byrow=TRUE)       # Nsex x Nlen
  n    <- sum(cmat)
  clen <- colSums(cmat)                             # combined-sex comp
  L1 <- sum(clen*mids)/n
  L2 <- sum(clen*(mids-L1)^2)/n
  L3 <- sum(clen*(mids-L1)^3)/n
  L4 <- sum(clen*(mids-L1)^4)/n
  Mw  <- sum(cmat*WtLen)/n                          # sex-specific weights
  s2w <- sum(cmat*(WtLen-Mw)^2)/n
  list(L1=L1, L2=L2, L3=L3, L4=L4, Mw=Mw, s2w=s2w, n=n)
}

# --- the assessment method ---------------------------------------------------
Run_DelayDiff <- function(Isim, Istock, Year, Plot=F)
{
  cat("Running delay-difference (Fournier-Doonan) EM:", Isim, Istock, Year, "\n")
  DD <- Stock[[Istock]]$Ass$DD                      # EM options (TODO ReadIn.R)

  # 1. catch (single aggregated fishery for the first implementation)
  Catch <- rep(0, Year)
  for (Iyear in 1:Year) Catch[Iyear] <- sum(Stock[[Istock]]$Data$Catches[,,Iyear])

  # 2. effort = catch / CPUE for the chosen index (DD$Cpue_Area, DD$Cpue_Index,
  #    cf. Run_Tier4b); NA where no index -- see "Required changes" (1)
  IndexVl <- rep(NA, Year)
  Iarea <- DD$Cpue_Area
  rows <- which(Stock[[Istock]]$Data$IndexData.Used[Iarea,,3] == DD$Cpue_Index)
  for (r in rows) {
    TheYear <- Stock[[Istock]]$Data$IndexData.Used[Iarea,r,1] - Stock[[Istock]]$YrOffset
    if (TheYear >= 1 && TheYear <= Year)
      IndexVl[TheYear] <- Stock[[Istock]]$Data$IndexData.Used[Iarea,r,4]
  }
  Eobs <- Catch / IndexVl

  # 3. length-comp derived observations (Part: 0 = total catch, 2 = retained)
  Nlen <- length(Stock[[Istock]]$LoLenBin) - 1
  mids <- Stock[[Istock]]$LoLenBin[1:Nlen] + diff(Stock[[Istock]]$LoLenBin)/2
  Nsex <- Stock[[Istock]]$Nsex
  Mobs <- L1 <- L2 <- L3 <- L4 <- s2w <- nsamp <- rep(NA, Year)
  LD <- Stock[[Istock]]$Data$LengthData.Used
  rows <- which(LD[,4] == DD$Len_fleet & LD[,6] == DD$Len_part & LD[,2] > 0)
  for (r in rows) {
    TheYear <- LD[r,2] - Stock[[Istock]]$YrOffset
    if (TheYear >= 1 && TheYear <= Year) {
      mm <- DD_comp_moments(LD[r, 7+(1:(Nsex*Nlen))], mids,
                            Stock[[Istock]]$WtLen, Nsex, Nlen)
      L1[TheYear] <- mm$L1; L2[TheYear] <- mm$L2
      L3[TheYear] <- mm$L3; L4[TheYear] <- mm$L4
      Mobs[TheYear] <- mm$Mw; s2w[TheYear] <- mm$s2w; nsamp[TheYear] <- mm$n
    }
  }

  # 4. model data (2 groups: pre-fishable + fishable, as in the paper)
  data <<- list(
    Cobs  = matrix(Catch, 1, Year),  Eobs  = matrix(Eobs, 1, Year),
    Mobs  = matrix(Mobs, 1, Year),   s2w   = matrix(s2w, 1, Year),
    L1obs = matrix(L1, 1, Year),     L2obs = matrix(L2, 1, Year),
    L3obs = matrix(L3, 1, Year),     L4obs = matrix(L4, 1, Year),
    nsamp = matrix(nsamp, 1, Year),
    avail = matrix(c(0,1), 1, 2),    mat = c(0,1),
    kage = DD$kage, Amax = 100, gamma_sr = DD$gamma_sr,
    bwl = Stock[[Istock]]$WtLen_a[1],       # check WtLen_b ~ 3 first
    sigmaC = 0.02, sigmaE = DD$sigmaE, sigmaR = DD$sigmaR,
    lamM = DD$lamM, lamL = DD$lamL, UsePriors = 1,
    prRho = DD$prRho, prL = DD$prL, prEntry = DD$prEntry,
    prTauk = DD$prTauk, prQ1 = DD$prQ1, prQ2 = DD$prQ2,
    maxlen_g1 = DD$maxlen_g1, lamPen = 100)

  # 5. initial values + fit (pattern as in the standalone demo; restart loop
  #    as in Run_Tier4a); parameters/map built from DD prior means
  # TODO(wire): lift the init/parameters/map block from the demo section of
  #             fournier_doonan_delaydiff_RTMB.R
  model <- MakeADFun(f_dd, parameters, map=map,
                     control=list(eval.max=10000, iter.max=1000), silent=TRUE)
  fit <- nlminb(model$par, model$fn, model$gr)
  for (i in 1:5) fit <- nlminb(model$env$last.par.best, model$fn, model$gr)
  Report <- model$report(model$env$last.par.best)

  # 6. store estimates (ratpack convention, cf. Run_Tier4a lines ~2157-2159)
  Nhist <- Stock[[Istock]]$Nhist
  Stock[[Istock]]$Ass$SSB.estimates[Isim, Year-Nhist+1, 1, 1:Year]  <<- Report$RB
  Stock[[Istock]]$Ass$Depl.estimates[Isim, Year-Nhist+1, 1, 1:Year] <<- Report$Depl*100

  # 7. PLACEHOLDER HCR -- decide the real rule before MSE runs (header, item 5)
  Dfin <- Report$Depl[Year]
  mult <- max(0, min(1, (Dfin - DD$Dlim)/(DD$Dtarg - DD$Dlim)))
  RBC  <- DD$Htarg * mult * Report$Bavail[Year]
  return(rep(RBC, 50))
}
