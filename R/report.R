# Markdown report, CSV tables and JSON summary.

md_table <- function(df, digits = 2) {
  fmt <- function(x) {
    if (!is.numeric(x)) return(as.character(x))
    whole <- all(is.na(x) | (is.finite(x) & x == round(x)))
    out <- formatC(x, format = "f", digits = if (whole) 0 else digits, big.mark = ",")
    out[is.na(x)] <- "–"
    sub("^-(0\\.?0*)$", "\\1", out)                     # no "-0.0"
  }
  cells <- as.data.frame(lapply(df, fmt), stringsAsFactors = FALSE)
  align <- ifelse(sapply(df, is.numeric), "---:", "---")
  c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(align, collapse = "|"), "|"),
    apply(cells, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
usd_m <- function(x) sprintf("%s$%.1fm", ifelse(x < 0, "-", ""), abs(x) / 1e6)

write_outputs <- function(res, out = "output") {
  fig <- file.path(out, "figures"); tab <- file.path(out, "tables")
  dir.create(fig, recursive = TRUE, showWarnings = FALSE); dir.create(tab, recursive = TRUE, showWarnings = FALSE)

  save_plot(plot_rules(res$sample, res$inertial, res$static_full), file.path(fig, "policy_rules.png"))
  save_plot(plot_deviation(res$sample), file.path(fig, "rule_deviation.png"), h = 4)
  save_plot(plot_rolling(res$rolling), file.path(fig, "rolling_coefficients.png"), h = 4)
  save_plot(plot_scenarios(res$sample, res$paths), file.path(fig, "scenarios.png"), h = 7.5)
  save_plot(plot_markets(res$markets), file.path(fig, "scenario_markets.png"), w = 10, h = 3.8)
  save_plot(plot_oos(res$oos), file.path(fig, "oos_forecasts.png"), h = 4)

  w <- function(x, f) utils::write.csv(x, file.path(tab, f), row.names = FALSE)
  w(res$static_full$coefs, "taylor_static_full.csv"); w(res$static_greenspan$coefs, "taylor_static_1987_2008.csv")
  w(res$inertial$coefs, "taylor_inertial_quarterly.csv"); w(res$inertial_monthly$coefs, "taylor_inertial_monthly.csv")
  w(res$ar$table, "ar_order_selection.csv"); w(res$persistence, "persistence_by_chair.csv")
  w(res$oos_summary, "oos_accuracy.csv"); w(res$regimes, "errors_by_regime.csv"); w(res$deviations, "rule_deviation_episodes.csv")
  w(res$paths, "scenario_rate_paths.csv"); w(res$markets, "scenario_markets.csv"); w(res$pnl, "scenario_duration_pnl.csv")
  w(res$spreads$comparison, "spread_model_comparison.csv"); w(res$yields$pass_through, "yield_pass_through.csv")
  w(ccar_table(res), "ccar_scenario_table.csv")

  jsonlite::write_json(summary_list(res), file.path(out, "summary.json"), auto_unbox = TRUE, digits = 6, pretty = TRUE)
  writeLines(report_md(res), file.path(out, "REPORT.md"))
  invisible(out)
}

# Quarterly scenario table in the layout of the Federal Reserve's published CCAR/DFAST scenario files.
ccar_table <- function(res) {
  m <- res$markets
  data.frame(scenario = m$scenario, date = qlabel(m$date), core_pce_inflation = round(m$core_pce, 2),
             output_gap = round(m$output_gap, 2), unemployment_rate = round(m$unrate, 2),
             fed_funds_rate = round(m$ff, 2), treasury_2y = round(m$gs2, 2), treasury_10y = round(m$gs10, 2),
             baa_spread = round(m$baa_spread, 2), baa_yield = round(m$baa_yield, 2))
}

summary_list <- function(res) {
  last_q <- function(sc) { x <- res$markets[res$markets$scenario == sc, ]; x[which.max(x$quarter), ] }
  list(
    sample = list(quarterly = paste(qlabel(range(res$sample$date)), collapse = " to "), quarters = nrow(res$sample),
                  monthly = paste(format(range(res$monthly$date), "%Y-%m"), collapse = " to "), months = nrow(res$monthly),
                  jump_off = qlabel(res$jump_off$date)),
    r2 = list(taylor_1993_full = res$taylor_1993_r2[["full"]], taylor_1993_1987_2008 = res$taylor_1993_r2[["pre_zlb_1987_2008"]],
              static_full = res$static_full$r2, static_1987_2008 = res$static_greenspan$r2,
              inertial_quarterly = res$inertial$r2, inertial_quarterly_changes = res$inertial$r2_changes,
              inertial_monthly = res$inertial_monthly$r2, inertial_monthly_changes = res$inertial_monthly$r2_changes,
              ar1_quarterly = res$ar1$r2, ar1_monthly = res$ar1_monthly$r2, ar_best_quarterly = res$ar$best$r2),
    inertial = list(rho_quarterly = res$inertial$rho, half_life_quarters = res$inertial$half_life_quarters,
                    long_run_inflation = res$inertial$long_run["inflation", "estimate"],
                    long_run_gap = res$inertial$long_run["output_gap", "estimate"], rho_monthly = res$inertial_monthly$rho),
    ar_best_p = res$ar$best_p,
    oos = res$oos_summary,
    breaks = list(dates = qlabel(res$breaks$breakpoints), sup_f = res$breaks$sup_f, p_value = res$breaks$sup_f_p),
    scenarios_end = lapply(setNames(nm = c("baseline", "hawkish", "dovish")), function(sc) {
      x <- last_q(sc); list(date = qlabel(x$date), ff = x$ff, gs2 = x$gs2, gs10 = x$gs10, baa_spread = x$baa_spread)
    }),
    duration_pnl = res$pnl
  )
}

report_md <- function(res) {
  s <- res$sample; jo <- res$jump_off; inr <- res$inertial; im <- res$inertial_monthly
  pnl <- res$pnl; mk <- res$markets
  tot <- stats::aggregate(total_pnl ~ scenario, data = pnl, sum)
  end <- mk[mk$quarter == max(mk$quarter), ]
  sc_tab <- do.call(rbind, lapply(c("baseline", "hawkish", "dovish"), function(sc) {
    p <- res$paths[res$paths$scenario == sc, ]; e <- end[end$scenario == sc, ]
    data.frame(scenario = SCENARIOS[[sc]]$label, `peak funds rate` = max(p$ff), `trough funds rate` = min(p$ff),
               `funds rate end` = e$ff, `80% band end` = sprintf("%.2f-%.2f", p$ff_p10[9], p$ff_p90[9]),
               `Taylor 1993 end` = p$taylor_1993[9], `2y end` = e$gs2, `10y end` = e$gs10, `Baa spread end` = e$baa_spread,
               check.names = FALSE)
  }))
  c(
    "# Results report", "",
    sprintf("Quarterly sample %s (%d quarters); monthly sample %s (%d months). Scenario jump-off %s: funds rate %.2f%%, core PCE %.2f%%, output gap %.2f%%.",
            paste(qlabel(range(s$date)), collapse = " to "), nrow(s), paste(format(range(res$monthly$date), "%Y-%m"), collapse = " to "),
            nrow(res$monthly), qlabel(jo$date), jo$ff, jo$core_pce, jo$output_gap), "",
    "## 1. How much of the policy rate do the models explain?", "",
    md_table(data.frame(model = c("Taylor (1993), fixed coefficients", "Taylor (1993), 1987Q3-2008Q2 only", "Estimated Taylor rule (static)",
                                  "Estimated Taylor rule, 1987Q3-2008Q2", "AR(1), quarterly", sprintf("AR(%d), quarterly (BIC choice)", res$ar$best_p),
                                  "Inertial Taylor rule, quarterly", "AR(1), monthly", "Inertial Taylor rule, monthly"),
                        `R2 (levels)` = c(res$taylor_1993_r2[["full"]], res$taylor_1993_r2[["pre_zlb_1987_2008"]], res$static_full$r2,
                                          res$static_greenspan$r2, res$ar1$r2, res$ar$best$r2, inr$r2, res$ar1_monthly$r2, im$r2),
                        `R2 (quarterly / monthly changes)` = c(NA, NA, NA, NA, NA, NA, inr$r2_changes, NA, im$r2_changes),
                        check.names = FALSE), 3), "",
    sprintf("The inertial rule explains %s of the monthly level of the funds rate and %s quarterly, but AR(1) alone already explains %s and %s: the fit comes mainly from rate persistence. On *changes* the rule explains %s (monthly) and %s (quarterly).",
            pct(im$r2), pct(inr$r2), pct(res$ar1_monthly$r2), pct(res$ar1$r2), pct(im$r2_changes), pct(inr$r2_changes)), "",
    "![rules](figures/policy_rules.png)", "",
    "### Estimated rules (Newey-West standard errors)", "",
    "Static rule, full sample:", "", md_table(res$static_full$coefs, 3), "",
    "Static rule, 1987Q3-2008Q2:", "", md_table(res$static_greenspan$coefs, 3), "",
    "Inertial rule, quarterly:", "", md_table(inr$coefs, 3), "",
    sprintf("Smoothing rho = %.3f (half-life %.1f quarters). Long-run responses: inflation %.2f (s.e. %.2f), output gap %.2f (s.e. %.2f). %s",
            inr$rho, inr$half_life_quarters, inr$long_run["inflation", 1], inr$long_run["inflation", 2],
            inr$long_run["output_gap", 1], inr$long_run["output_gap", 2],
            if (inr$long_run["inflation", 1] > 1) "The long-run inflation response exceeds 1 (the Taylor principle)." else "The long-run inflation response is below 1 (the Taylor principle fails)."), "",
    "## 2. Rate persistence across cycles (AR(1) by Fed chair)", "", md_table(res$persistence, 3), "",
    "## 3. Out-of-sample accuracy (expanding window from 2000Q1)", "", md_table(res$oos_summary, 3), "",
    "The inertial rule's forecast uses the macro data that actually materialised, so it is a *conditional* forecast, the way it is used for scenarios.", "",
    "![oos](figures/oos_forecasts.png)", "",
    "## 4. Model limitations", "", md_table(res$regimes, 2), "",
    sprintf("Structural breaks (Bai-Perron, static rule): %s. sup-F = %.1f (%s).",
            paste(qlabel(res$breaks$breakpoints), collapse = ", "), res$breaks$sup_f,
            if (res$breaks$sup_f_p < 0.001) "p < 0.001" else sprintf("p = %.3f", res$breaks$sup_f_p)), "",
    "![rolling](figures/rolling_coefficients.png)", "",
    "### Where systematic rules and Fed discretion diverged (|deviation from Taylor 1993| > 2pp for 2+ quarters)", "",
    md_table(res$deviations, 2), "", "![deviation](figures/rule_deviation.png)", "",
    "## 5. Scenario rate paths (9 quarters, CCAR/DFAST layout)", "", md_table(sc_tab, 2), "",
    "![scenarios](figures/scenarios.png)", "",
    "## 6. Market and credit risk translation", "",
    "Expectations regressions (yield on average funds rate over the next 8 quarters + core inflation, 1987Q3 onward):", "",
    md_table(rbind(cbind(yield = "2-year", res$yields$gs2$coefs), cbind(yield = "10-year", res$yields$gs10$coefs)), 3), "",
    "Short-run pass-through of a 1pp funds-rate change within the quarter:", "", md_table(res$yields$pass_through, 3), "",
    sprintf("Baa spread model (chosen by BIC among %d candidates: `%s`):", nrow(res$spreads$comparison), res$spreads$spec), "",
    md_table(res$spreads$comparison[, c("spec", "r2", "bic", "terms")], 3), "",
    "![markets](figures/scenario_markets.png)", "",
    "### Duration and spread P&L on $100m per position (end of horizon, price return)", "",
    md_table(transform(pnl[, c("scenario", "position", "change_rate_bp", "change_spread_bp", "rate_pnl", "spread_pnl", "total_pnl")],
                       rate_pnl = rate_pnl / 1e6, spread_pnl = spread_pnl / 1e6, total_pnl = total_pnl / 1e6), 1), "",
    paste0("Portfolio totals ($m): ", paste(sprintf("%s %.1f", tot$scenario, tot$total_pnl / 1e6), collapse = "; "), ".")
  )
}
