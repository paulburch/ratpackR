# ============================================================================
# test_DelayDiff_seeds.R -- estimation performance of Run_DelayDiff over
# simulated data sets (seeds 301-310), using the data and settings of
# test_Run_DelayDiff.R, for the base settings and three variants.
# Run from the repository root.  Reports the estimated vs true final
# depletion (fishable biomass / unfished) and the median relative errors.
# ============================================================================
lines <- readLines("MISC HCR/test_Run_DelayDiff.R")
txt <- paste(lines[1:grep("^DeplTrue", lines)], collapse="\n")
cfgs <- list(base=list(), lamM1=list(lamM=1), Q1prior=list(Q1sd=0.7), allrecdev=list(RecDevLead=40))
out <- NULL
for (seed in 301:310) {
  eval(parse(text=sub("set.seed(202)", sprintf("set.seed(%d)", seed), txt, fixed=TRUE)))
  Base <- Stock
  row <- c(seed=seed, true=DeplTrue[40])
  for (nm in names(cfgs)) {
    Stock <- Base; for (o in names(cfgs[[nm]])) Stock[[1]]$Ass$DD[[o]] <- cfgs[[nm]][[o]]
    r <- try({invisible(capture.output(TACs <- Run_DelayDiff(1, 1, 40))); DD.Last.Fit$Report$Depl[40]}, silent=TRUE)
    row[nm] <- if (inherits(r, "try-error")) NA else r
  }
  out <- rbind(out, row)
}
print(round(out, 3))
re <- (out[,-(1:2)] - out[,"true"]) / out[,"true"]
cat("median rel error:\n"); print(round(apply(re, 2, median, na.rm=TRUE), 3))
cat("median |rel error|:\n"); print(round(apply(abs(re), 2, median, na.rm=TRUE), 3))
