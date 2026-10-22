#!/usr/bin/env Rscript
# Quantitative analysis of US monetary policy: Taylor-rule and autoregressive models of the federal funds rate,
# CCAR/DFAST-style scenario rate paths and their market and credit risk implications.
#
# Usage:  Rscript run_analysis.R            (uses cached FRED data in data/raw if present)
#         Rscript run_analysis.R --refresh  (re-downloads every series)

local_lib <- file.path(getwd(), ".Rlib")
if (dir.exists(local_lib)) .libPaths(c(local_lib, .libPaths()))
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f)

refresh <- "--refresh" %in% commandArgs(trailingOnly = TRUE)
res <- run_all(refresh = refresh)
write_outputs(res, "output")

cat(sprintf("Sample %s, jump-off %s\n", paste(qlabel(range(res$sample$date)), collapse = " to "), qlabel(res$jump_off$date)))
cat(sprintf("Inertial Taylor rule R2: %.3f monthly, %.3f quarterly (changes: %.3f / %.3f)\n",
            res$inertial_monthly$r2, res$inertial$r2, res$inertial_monthly$r2_changes, res$inertial$r2_changes))
for (sc in c("baseline", "hawkish", "dovish")) {
  p <- res$paths[res$paths$scenario == sc, ]
  cat(sprintf("%-8s funds rate %s: %.2f%%\n", sc, qlabel(max(p$date)), tail(p$ff, 1)))
}
cat("Outputs written to output/ (see output/REPORT.md)\n")
