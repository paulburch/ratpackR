# Compare two sets of ratpackR result folders token by token (numeric tolerance 1e-8 relative).
# Usage: Rscript docs/bugfix/compare_runs.R <baseline_dir> <new_dir>
args <- commandArgs(trailingOnly = TRUE); A <- args[1]; B <- args[2]
fa <- list.files(A, pattern = "\\.Out$", recursive = TRUE)
fa <- fa[!grepl("Debug_|LogFile_", fa)]
norm <- function(f) sub("_E[0-9]+_00", "", basename(f))
for (f in fa) {
  g <- file.path(B, f)
  if (!file.exists(g)) { cat(sprintf("  %-55s MISSING in new run\n", f)); next }
  la <- readLines(file.path(A, f)); lb <- readLines(g)
  if (length(la) != length(lb)) { cat(sprintf("  %-55s line count %d -> %d\n", f, length(la), length(lb))); next }
  nd <- 0; maxr <- 0; first <- NA
  for (i in seq_along(la)) {
    ta <- strsplit(trimws(la[i]), " +")[[1]]; tb <- strsplit(trimws(lb[i]), " +")[[1]]
    if (identical(ta, tb)) next
    na <- suppressWarnings(as.numeric(ta)); nb <- suppressWarnings(as.numeric(tb))
    if (length(ta) != length(tb)) { nd <- nd + 1; if (is.na(first)) first <- i; next }
    num <- !is.na(na) & !is.na(nb)
    r <- abs(na[num] - nb[num]) / pmax(abs(na[num]), 1e-12)
    txt <- !num & ta != tb
    if (any(r > 1e-8) || any(txt)) { nd <- nd + 1; if (is.na(first)) first <- i; if (length(r)) maxr <- max(maxr, r[is.finite(r)], 0) }
  }
  cat(sprintf("  %-55s %s\n", f, if (nd == 0) "identical" else sprintf("%d of %d lines differ (max rel. diff %.3g; first at line %d)", nd, length(la), maxr, first)))
}
