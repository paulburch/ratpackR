# Parallel driver for ratpackR (rebuilt 2026-11 from the current RatpackR.R; bug review #17).
#
# This file no longer carries its own copy of the engine. It sources the current RatpackR.R
# (and through it R Inserts/*.R), so serial and parallel runs share one code base, and adds
#   DoRunParallel(GeneralFile, RunNo, n_cores)
# which runs the simulations of DoRun() on a socket cluster (works on Windows and Linux).
#
# Usage (from the repo root, after the usual run-flag block of a RunStreams script):
#   source("R Inserts/Parallel/RatpackR.R")
#   DoRunParallel(GeneralFile="General_Silver.warehou.OM", RunNo="Silver.warehou", n_cores=4)
#
# What it does, so results match the serial DoRun():
#  1. reads the general file, makes the same seeds (set.seed(1234)), and, for simulation 1
#     only, tunes R0 to the target depletion exactly as DoRun() does;
#  2. runs each simulation on a worker: SetSpec with that simulation's seeds, the R0
#     multipliers from step 1, Do.Project, and the usual Write* calls, but into per-simulation
#     files;
#  3. appends the per-simulation files, in simulation order, to the normal output files.
# Unlike DoRun(), all simulations are run whatever Estimation.test is (DoRun() stops after
# simulation 1 when Estimation.test < 90).
# Each worker compiles Model.cpp once (about 10 s). SS runs in its own SS_Sim_<Isim>_... folders.

source("RatpackR.R")

DoRunParallel <- function(GeneralFile, RunNo, n_cores = max(1, parallel::detectCores() - 1))
 {
  General <<- Read.General.File(GeneralFile, RunNo)
  if (TestCase==T) General$Nsim <<- 1
  write("", file=DebugFile)
  Nsim <- General$Nsim; Nstocks <- General$Nstocks

  # Seeds, exactly as in DoRun()
  TheSeeds <- 1234; set.seed(TheSeeds)
  Seeds <- matrix(nrow=Nsim, ncol=Nstocks)
  for (Isim in 1:Nsim) Seeds[Isim,] <- floor(runif(Nstocks, 1, 1000000))

  # Step 1: R0 tuning for simulation 1 (same code path as DoRun)
  Stock <<- vector(mode="list", length=Nstocks)
  R0Save1 <- vector(mode="list", length=Nstocks)
  R0mult <- rep(1, Nstocks)
  for (Istock in 1:Nstocks)
   {
    Stock[[Istock]] <<- SetSpec(1, Istock, General$Stock.Names[Istock], Seed=Seeds[1,Istock])
    R0Save1[[Istock]] <- list(Save1=Stock[[Istock]]$R00, Save2=Stock[[Istock]]$R00.orig, Save3=Stock[[Istock]]$R0)
   }
  if (General$MultiStock.Version=="Yes") ReviewFsolver()
  for (Istock in 1:Nstocks)
   if (!is.na(Stock[[Istock]]$Target.Depletion))
    {
     General$Do.any.projections <<- F
     R0mult.min <- 0; R0mult.max <- 10
     for (Iloop in 1:10)
      {
       R0mult[Istock] <- (R0mult.min+R0mult.max)/2.0
       Stock[[Istock]]$R00 <<- R0Save1[[Istock]]$Save1*R0mult[Istock]
       Stock[[Istock]]$R00.orig <<- R0Save1[[Istock]]$Save2*R0mult[Istock]
       Stock[[Istock]]$R0 <<- R0Save1[[Istock]]$Save3*R0mult[Istock]
       Stock[[Istock]]$Data$NindexData <<- rep(0,Stock[[Istock]]$NassArea)
       Stock[[Istock]]$Data$NdiscardData <<- 0
       Do.Project(1)
       YearProj <- Stock[[Istock]]$Nhist+1
       Depletion <- sum(Stock[[Istock]]$SSB[,YearProj])/sum(Stock[[Istock]]$SSB0*Stock[[Istock]]$R0[,YearProj]/Stock[[Istock]]$R00)
       cat(R0mult[Istock],Depletion,R0mult.min,R0mult.max,"\n")
       if (Depletion > Stock[[Istock]]$Target.Depletion) R0mult.max <- R0mult[Istock] else R0mult.min <- R0mult[Istock]
      }
     General$Do.any.projections <<- T
    }

  # Output files that DoRun() appends to, once per simulation
  OutNames <- c("BiolSaveName","LogName","ProjAllSaveName","ProjFleetSaveName","ProjFleetAreaSaveName",
                "EstSaveName","ParSaveName","AllParSaveName","InsuranceSaveName","MultiSaveName",
                "WASaveName","MiscSaveName")
  OutNames <- OutNames[OutNames %in% names(General)]
  for (nm in OutNames) if (nm != "BiolSaveName") unlink(paste0(Path, General[[nm]]))   # Biol header was written by Read.General.File
  GeneralTemplate <- General

  # Step 2: one simulation on a worker
  OneSim <- function(Isim)
   {
    setwd(Path)
    General <<- GeneralTemplate
    for (nm in OutNames) General[[nm]] <<- paste0(General[[nm]], ".sim", Isim)
    for (nm in OutNames) unlink(paste0(Path, General[[nm]]))
    DebugFile <<- paste0(DebugBase, ".sim", Isim); write("", file=DebugFile)   # per-simulation debug file (left in Results/)
    Stock <<- vector(mode="list", length=General$Nstocks)
    for (Istock in 1:General$Nstocks)
     {
      Stock[[Istock]] <<- SetSpec(Isim, Istock, General$Stock.Names[Istock], Seed=Seeds[Isim,Istock])
      if (!is.na(Stock[[Istock]]$Target.Depletion))
       {
        Stock[[Istock]]$R00 <<- R0Save1[[Istock]]$Save1*R0mult[Istock]
        Stock[[Istock]]$R00.orig <<- R0Save1[[Istock]]$Save2*R0mult[Istock]
        Stock[[Istock]]$R0 <<- R0Save1[[Istock]]$Save3*R0mult[Istock]
       }
     }
    if (General$MultiStock.Version=="Yes") ReviewFsolver()
    for (Istock in 1:General$Nstocks) WriteBiol(Istock,General$BiolSaveName,General$FolderResults)
    for (Istock in 1:General$Nstocks) WriteLog(Isim,Istock,General$LogName)
    Do.Project(Isim)
    for (Istock in 1:General$Nstocks) WriteProjFiles(Isim,Istock,General$ProjAllSaveName,General$ProjFleetSaveName,General$ProjFleetAreaSaveName)
    for (Istock in 1:General$Nstocks) WriteEst(Isim,Istock,General$EstSaveName,General$ParSaveName,General$AllParSaveName)
    for (Istock in 1:General$Nstocks) WriteInsurance(Isim,Istock,General$InsuranceSaveName)
    WriteMulti(Isim,General$MultiSaveName)
    for (Istock in 1:General$Nstocks) WriteWA(Isim,Istock,General$WASaveName)
    for (Istock in 1:General$Nstocks) WriteMisc(Isim,Istock,General$MiscSaveName)
    setwd(Path)
    return(Isim)
   }

  # Run flags and objects the workers need (everything a RunStreams script sets globally)
  Flags <- c("Path","Input.Folder","TestCase","IsJitter","Deter.Rec.devs","Deter.Index.data","Deter.Discard.data",
             "Deter.Length.data","Deter.Age.data","Huge.sample.sizes","FullOutput","Estimation.test")
  Flags <- Flags[sapply(Flags, exists, envir=globalenv())]
  cat("Running", Nsim, "simulations on", n_cores, "workers\n")
  cl <- parallel::makePSOCKcluster(n_cores)
  on.exit({ parallel::stopCluster(cl); setwd(Path) }, add=TRUE)
  parallel::clusterExport(cl, Flags, envir=globalenv())
  parallel::clusterEvalQ(cl, { setwd(Path); suppressPackageStartupMessages({ library(r4ss); library(RTMB); library(Rcpp) }); source("RatpackR.R"); NULL })
  DebugBase <- DebugFile
  parallel::clusterExport(cl, c("Seeds","R0Save1","R0mult","OutNames","GeneralTemplate","OneSim","DebugBase"), envir=environment())
  Done <- parallel::parLapplyLB(cl, 1:Nsim, function(Isim) tryCatch(OneSim(Isim), error=function(e) paste("Simulation", Isim, "failed:", conditionMessage(e))))
  Failed <- Filter(is.character, Done)

  # Step 3: append per-simulation files in simulation order
  for (nm in OutNames)
   for (Isim in 1:Nsim)
    {
     f <- paste0(Path, GeneralTemplate[[nm]], ".sim", Isim)
     if (file.exists(f)) { file.append(paste0(Path, GeneralTemplate[[nm]]), f); unlink(f) }
    }
  if (length(Failed) > 0) { for (m in Failed) cat(m, "\n"); stop(length(Failed), " simulation(s) failed") }
  cat("done projecting (parallel)\n")
  invisible(TRUE)
 }
