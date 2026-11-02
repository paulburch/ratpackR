# Reproducible checks for docs/bug_review.md (Paul's addition; does not modify André's code).
# Run from the repo root:   Rscript docs/bug_checks.R
# Needs the Linux set-up (setup_linux.sh). Uses copies of the Silver.warehou inputs from
# "Inputs Buffer/" placed under Temp/BugChecks/ (git-ignored). Takes ~30 s.
# Each check prints  [CONFIRMED] <id> ...  when the suspected behaviour is reproduced,
# or [NOT REPRODUCED] otherwise.
options(warn = 1)
Path <- sub("/*$", "/", Sys.getenv("RATPACK_ROOT", unset = getwd())); setwd(Path)
suppressPackageStartupMessages({ library(r4ss); library(RTMB); library(Rcpp) })

# --- load the code ----------------------------------------------------------------
for (f in c("ReadIn", "WriteOut", "Assessment", "DataGen")) source(paste0("R Inserts/", f, ".R"))
sourceCpp("R Inserts/Model.cpp")
# function definitions from RatpackR.R without re-running its top-level source()/sourceCpp()
for (e in parse("RatpackR.R"))
  if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")))
    eval(e, globalenv())

TestCase <- F; IsJitter <- F; Deter.Rec.devs <- F; Deter.Index.data <- T; Deter.Discard.data <- T
Deter.Length.data <- T; Deter.Age.data <- T; Huge.sample.sizes <- F; FullOutput <- F; Estimation.test <- 1

res <- function(id, ok, msg) cat(sprintf("[%s] %s %s\n", if (isTRUE(ok)) "CONFIRMED" else "NOT REPRODUCED", id, msg))
err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))

# --- reduced copies of the Silver.warehou inputs -------------------------------------
Input.Folder <- "Temp/BugChecks/"
dir.create(Input.Folder, recursive = TRUE, showWarnings = FALSE)
Sp <- "Silver.warehou"
for (f in c(paste0("General_", Sp, ".OM"), paste0(Sp, c(".OM", ".EM", ".OM.SAV", ".EM.SAV"))))
  file.copy(paste0("Inputs Buffer/", f), paste0(Input.Folder, f), overwrite = TRUE)
g <- readLines(paste0(Input.Folder, "General_", Sp, ".OM"))
g <- sub("^#Number_of_simulations.*", "#Number_of_simulations 1", g)
g <- sub("^#Number_of_projection_years.*", "#Number_of_projection_years 1", g)
writeLines(g, paste0(Input.Folder, "General_", Sp, ".OM"))
OMlines <- readLines(paste0(Input.Folder, Sp, ".OM")); EMlines <- readLines(paste0(Input.Folder, Sp, ".EM"))
load_stock <- function(om = OMlines, em = EMlines) {
  writeLines(om, paste0(Input.Folder, Sp, ".OM")); writeLines(em, paste0(Input.Folder, Sp, ".EM"))
  General <<- Read.General.File(paste0("General_", Sp, ".OM"), "BugChecks")
  Stock <<- vector("list", 1)
  Stock[[1]] <<- suppressWarnings(SetSpec(1, 1, Sp, Seed = 1234))
}
invisible(capture.output(load_stock()))
base <- Stock[[1]]; Gen0 <- General

# B01 SetBuffer: the default Buffer is computed then overwritten
s <- base; s$Ass$Buffer <- 0.8; s$Ass$Stale.rate <- 0; s$Ass$Min.Buffer <- 0; Stock[[1]] <- s
out <- SetBuffer(1, c(100, 100, 100))
res("B01", all(out == 100), sprintf("SetBuffer(Buffer=0.8, Stale.rate=0, Min.Buffer=0) on TAC 100 returns %s (expected 80)", paste(out, collapse = ",")))
Stock[[1]] <- base

# B02 FixedCosts read from column 5 of the 4-column #Econ_parameters block -> NA costs
res("B02", all(is.na(base$FixedCosts)), sprintf("Stock$FixedCosts = %s; Price = %s", paste(base$FixedCosts, collapse = ","), paste(base$Price, collapse = ",")))
Proj <- list(nsex = 1, nagebins = 3, endyr = 10, nfleet = 1, baseM = 0.2, Fecund = c(0, 1, 1), SelAge = matrix(1, 1, 3),
             SelAgeRetWght = matrix(1, 1, 3), Exploit = 1, NatAge = c(100, 80, 60), R0 = 100, Nyear = 2, Nsim = 1,
             TAC_Year1 = 10, RecDevs = matrix(0, 3, 1), MDevs = matrix(0, 3, 1), Price = base$Price[1], CostPerDay = 1,
             DaysPerF1 = 1, DaysPerF2 = 1, FixedCosts = base$FixedCosts[1], SSB0 = 200, Ftarget = 0.1, Inflect = 0.4, CutOff = 0.2)
p <- Project(Proj)
NetLoss <- 0 - p$Profit[1, 1]
res("B02b", is.na(p$Profit[1, 1]) && !is.na(err(if (NetLoss > 0 & TRUE) 1)),
    sprintf("Model.cpp Project() Profit = %s; Do.Insurance's `if (NetLoss > 0 & ...)` then fails: '%s'", p$Profit[1, 1], err(if (NetLoss > 0 & TRUE) 1)))

# B03 Catch bias: only the first fleet's row is read, and the final value is not filled
om <- OMlines; L <- grep("^#Catch:Base_Bias", om)
om[L + 1] <- "2 1990 0.8 2000 1.2"; om[L + 2] <- "2 1990 0.5 2000 0.5"
invisible(capture.output(load_stock(om)))
cb <- Stock[[1]]$Data$Catch.Bias; yo <- Stock[[1]]$YrOffset
res("B03a", isTRUE(all.equal(cb[1, , 1], cb[1, , 2])), sprintf("fleet 2 spec is 0.5 throughout, but Catch.Bias[,1990,2] = %.2f (fleet 1's value)", cb[1, 1990 - yo, 2]))
res("B03b", cb[1, 2010 - yo, 1] == 1, sprintf("fleet 1 spec ends at 1.2 from 2000, but Catch.Bias in 2010 = %.2f, in %d = %.2f", cb[1, 2010 - yo, 1], dim(cb)[2] + yo, cb[1, dim(cb)[2], 1]))

# B04 Early R0 multiplier block end: written to .end.yrs, read as _end_yrs
om <- c(OMlines, "#Early_R0Mult -0.3", "#Early_R0Mult_Block_end 1 10")
invisible(capture.output(load_stock(om)))
s <- Stock[[1]]
res("B04", identical(s$Early.R0.mult_end_yrs, c(0, 0)) && identical(s$Early.R0.mult.end.yrs, c(1, 10)),
    sprintf("Early.R0.mult_end_yrs = (%s) used at RatpackR.R:1146; Early.R0.mult.end.yrs = (%s) holds the input",
            paste(s$Early.R0.mult_end_yrs, collapse = ","), paste(s$Early.R0.mult.end.yrs, collapse = ",")))

# B05 Steepness bias multiplier ignored by Write_ctl when > 0
em <- EMlines; L <- grep("^#SS:parameter_Steep_bias", em)
if (length(L)) em[L] <- "#SS:parameter_Steep_bias 0.8" else em <- c(em, "#SS:parameter_Steep_bias 0.8")
invisible(capture.output(load_stock(em = em)))
Fold <- paste0(Path, "Temp/BugChecks/ctl/"); dir.create(Fold, showWarnings = FALSE)
Stock[[1]]$Data$Catches[1, , 1:Stock[[1]]$Nhist] <- 1
Write_ctl(Fold, 1, 1, Stock[[1]]$Nhist)
st <- as.numeric(strsplit(trimws(grep("# SR_BH_steep", readLines(paste0(Fold, "data.ctl")), value = TRUE)), " +")[[1]][3])
res("B05", abs(st - Stock[[1]]$Ass$SR_Steep) < 1e-12, sprintf("SS_Steep_Bias = %.1f, true h = %.3f, EM initial h written = %.3f (M bias is applied the same way and works)", Stock[[1]]$Ass$SS_Steep_Bias, Stock[[1]]$Ass$SR_Steep, st))
invisible(capture.output(load_stock()))

# B06 Tier 4b compares CPUE with the *multiplier* via partial matching
T4b <- list(Cpue_limit_mult = 0.4)
res("B06", identical(T4b$Cpue_lim, 0.4), "Ass$Tier4b$Cpue_lim partially matches Cpue_limit_mult (0.4), not the limit CPUE")

# B07 DataGen discard-age expected values use Stock[[Iarea,Istock]]
res("B07", !is.na(err(base_list <- list(base)[[1, 1]])), sprintf("Stock[[1,1]] on a list: '%s'", err(list(base)[[1, 1]])))

# B08 TAC.mat reshape with byrow=T scrambles fleets when NassArea > 1 (RatpackR.R:1343)
TACs <- array(0, dim = c(1, 2, 3, 50)); TACs[1, 1, , 1] <- c(10, 20, 30); TACs[1, 2, , 1] <- c(1, 2, 3)
TheCat <- apply(matrix(TACs[1, , , 1], nrow = 2, ncol = 3, byrow = T), 2, sum)
res("B08", !isTRUE(all.equal(TheCat, c(11, 22, 33))), sprintf("by-fleet TAC should be 11,22,33; code gives %s", paste(TheCat, collapse = ",")))

# B09 Allocation loop variable is Istocks but the body uses Istock
dp <- deparse(Do.Project)
res("B09", length(grep("Istocks", dp)) == 1 && length(grep("for \\(Istocks in 1:Nstocks\\)", dp)) == 1,
    "Do.Project: `for(Istocks in 1:Nstocks)` is the only use of Istocks; the body indexes Stock[[Istock]] and TACs[Istock,...] (Istock = Nstocks from the previous loop)")

# B10 SPR_ref / Get.Initial with 2 areas and one-way movement (synthetic stock)
General <- list(Narea = 2, Nfleet = 1, Ncat_fleet = 1)
A <- 4; Mv <- array(0, c(2, 2, A)); Mv[1, 1, ] <- 0.7; Mv[1, 2, ] <- 0.3; Mv[2, 2, ] <- 1   # area 1 -> area 2 only
Mv[1, 1, 3] <- 1; Mv[1, 2, 3] <- 0                                                           # no movement into age index 3
syn <- list(MaxAge = A, Nsex = 1, M = array(0.2, c(1, A, 1)), SelAge = array(c(0, 1, 1, 1), c(1, 1, A, 1)), Move = Mv,
            Relative.Density = c(1, 0), R00 = c(1, 0), SelexAge = array(1, c(1, 1, A, 1)), FracLenM = array(1, c(1, A, 1, 1)),
            SelSelLen = array(1, c(1, 1, 1, 1)), RetSelAge = array(1, c(1, 1, A, 1)), RetSelLen = array(1, c(1, 1, 1, 1)),
            WtLen = matrix(1, 1, 1), Fecundity = matrix(c(0, 1, 1, 1), A, 1))
Stock <- list(syn)
sp <- SPR_ref(1, Fmult = 0, AveF = matrix(0.1, 2, 1), Iyear = 1)
# Reference: run the Project.One.Ahead update rule (RatpackR.R:563-582) to equilibrium with recruits R00
N <- matrix(0, 2, A)
for (y in 1:300) { Nn <- matrix(0, 2, A); S <- N * exp(-0.2)
  for (a in 2:A) for (i in 1:2) for (j in 1:2) Nn[j, a] <- Nn[j, a] + Mv[i, j, a] * S[i, a - 1]
  for (i in 1:2) for (j in 1:2) Nn[j, A] <- Nn[j, A] + Mv[i, j, A] * S[i, A]
  Nn[, 1] <- syn$R00; N <- Nn }
res("B10a", sum(sp$Ninit[2, 1, ]) == 0 && sum(N[2, ]) > 0,
    sprintf("SPR_ref F=0: numbers in area 2 = %.3f (movement ignored); projection rule gives %.3f", sum(sp$Ninit[2, 1, ]), sum(N[2, ])))
b <- body(Do.Project); gi <- NULL
for (k in seq_along(b)) if (is.call(b[[k]]) && identical(b[[k]][[2]], as.name("Get.Initial"))) gi <- eval(b[[k]][[3]])
gin <- gi(1)$Ninit[, 1, ]
res("B10b", max(abs(gin - N)) > 1e-6, sprintf("Get.Initial equilibrium vs projection-rule equilibrium differ by up to %.3f (movement uses age a-1 vs a)", max(abs(gin - N))))
syn2 <- syn; syn2$Relative.Density <- c(0.5, 0.5); syn2$Move <- array(0, c(2, 2, A)); syn2$Move[1, 1, ] <- 1; syn2$Move[2, 2, ] <- 1
Stock <- list(syn2)
c1 <- SPR_ref(1, Fmult = 1, AveF = matrix(c(0.1, 0.1), 2, 1), Iyear = 1)$CatR
syn3 <- syn2; syn3$Relative.Density <- c(0.5, 0)
Stock <- list(syn3); c2 <- SPR_ref(1, Fmult = 1, AveF = matrix(c(0.1, 0.1), 2, 1), Iyear = 1)$CatR
res("B10c", c2 == 0 && c1 > 0,
    sprintf("SPR_ref catch with two identical areas = %.4f; with area 2 empty (area 1 unchanged) = %.4f (should be half of the first); only Iarea = Narea is summed", c1, c2))

# B11 TAC.management == "No": TACsOrig is a 2-D matrix (or undefined) but indexed with 3 subscripts
res("B11", !is.na(err(matrix(0, 4, 50)[1, 1, ])), sprintf("TACsOrig[Istock,IassArea,] on a matrix: '%s'", err(matrix(0, 4, 50)[1, 1, ])))

# B12 ReviewFsolver indexes the 3-D F.Selex.Inp with 2 subscripts (CatchType 3)
res("B12", !is.na(err(base$F.Selex.Inp[, 1])), sprintf("F.Selex.Inp[,Ifleet] (dims %s): '%s'", paste(dim(base$F.Selex.Inp), collapse = "x"), err(base$F.Selex.Inp[, 1])))

# B13 Rec-dev bias ramp (Assessment.R:1233) mixes calendar and model years
Year <- 46; YrOffset <- 1979; lf <- -6; er <- 0
Iyr <- (Year + lf):(Year + er); bias <- (Year + lf + YrOffset - Iyr) / (er - lf + YrOffset)
res("B13", all(bias > 0.98), sprintf("descending ramp should run 1 -> 0 over %d-%d; formula gives %s", min(Iyr) + YrOffset, max(Iyr) + YrOffset, paste(round(bias, 3), collapse = ",")))

# B14 PGMSY divides by the primary stock's recent catch by fleet (0 -> NaN/Inf)
General <- list(Nstocks = 2, Ncat_fleet = 2, PGMSY.Primary.Species = c(0, 1), PGMSY.Primary.Species.by.fleet = c(1, 1),
                Multi = list(Link.Species = matrix(0, 2, 2), PGMSY.Adjustment = matrix(1, 2, 2)))
DebugFile <- tempfile()
mk <- function(cat) list(Nhist = 10, CatchRetained = array(rep(cat, each = 1), c(1, 2, 20)), Ass = list(Min.TAC = 0))
Stock <- list(mk(c(100, 0)), mk(c(10, 10)))
Stock[[1]]$CatchRetained[1, 2, ] <- 0
TACs <- array(0, c(2, 1, 2, 50)); TACs[1, 1, , 1] <- c(100, 0); TACs[2, 1, , 1] <- c(5, 5)
e1 <- err(invisible(capture.output(PGMSY(TACs, 1))))
TACs[1, 1, 2, 1] <- 1
out <- NULL; invisible(capture.output(out <- PGMSY(TACs, 1)))
res("B14", !is.na(e1) || any(!is.finite(out)) || sum(out[1, 1, , 1]) == 0,
    sprintf("primary stock with no recent catch on fleet 2: TAC 0 -> error '%s'; TAC 1 -> primary TAC becomes %s", e1, paste(round(out[1, 1, , 1], 3), collapse = ",")))

# B15 Discard data are generated per assessment area but indexed as if they were biological areas: inspection only.

# B16 Random-number streams are re-used: discard devs reseed with the original Seed (ReadIn.R:1245)
set.seed(1234); a <- floor(runif(1, 1, 1e6)); set.seed(a); b2 <- floor(runif(1, 1, 1e6)); set.seed(b2); c3 <- floor(runif(1, 1, 1e6))
u <- runif(3, 0, 1)                       # = the catastrophic-M draws (ReadIn.R:179) for years 1-3
res("B16", all(base$Data$Age.seeds[1, 1, 1, 1:3] == floor(1 + u * (1e6 - 1))),
    sprintf("Age.seeds[1,1,1,1:3] = %s = floor(1+U*999999) for the same U that decide catastrophic M in years 1-3", paste(base$Data$Age.seeds[1, 1, 1, 1:3], collapse = ",")))

# B17 Is_* flags are character; R Inserts/Parallel/Assessment.R sums them as logicals
res("B17", !is.na(err(sum(base$Data$Is_discard))), sprintf("sum(Stock$Data$Is_discard) ('%s'): '%s'", paste(unlist(base$Data$Is_discard), collapse = ","), err(sum(base$Data$Is_discard))))

# B18 Initial LengthData dummy row is one column short of the rows DataGen appends
res("B18", length(base$Data$LengthData) == 6 + base$Nsex * base$Nlen,
    sprintf("LengthData seed row has %d columns, DataGen rows have %d", length(base$Data$LengthData), 7 + base$Nsex * base$Nlen))

# B19 Catch-fleet index predictions apply age selectivity twice (SelexAge * SelRetWghtAge, RatpackR.R:552)
ix <- which(unlist(base$Data$Is_index) == "Yes" & seq_len(Gen0$Nfleet) <= Gen0$Ncat_fleet)
sx <- base$SelexAge[, ix, , ]
cat(sprintf("[INFO] B19 indexed catch fleets %s: %d of %d SelexAge values lie strictly between 0 and 1, so the double count %s for this stock\n",
    paste(ix, collapse = ","), sum(sx > 0 & sx < 1), length(sx), if (any(sx > 0 & sx < 1)) "changes the simulated CPUE" else "has no effect"))

# B20 Run_Tier4a maps 'logr' (no such parameter) when EstR="No", EstZ="Yes"
pars <- list(logR = 0, logK = 1); f <- function(p) { getAll(p); (logR - 1)^2 + (logK - 2)^2 }
e20 <- err(MakeADFun(f, pars, map = list(logr = factor(NA)), silent = TRUE))
obj <- tryCatch(MakeADFun(f, pars, map = list(logr = factor(NA)), silent = TRUE), error = function(e) NULL)
res("B20", is.null(obj) || length(obj$par) == 2, sprintf("map=list(logr=NA): %s", if (is.null(obj)) e20 else paste("still estimates", length(obj$par), "parameters, logR not fixed")))
cat("done\n")
