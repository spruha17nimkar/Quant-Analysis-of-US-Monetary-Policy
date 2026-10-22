# Runs every model and collects the results in one list.

run_all <- function(refresh = FALSE, oos_start = "2000-01-01") {
  d <- build_dataset(refresh = refresh)
  s <- model_sample(d)
  greenspan <- model_sample(d, start = "1987-07-01", end = "2008-07-01")   # pre-ZLB benchmark sample
  monthly <- build_monthly(refresh = refresh)

  taylor_fit <- c(full = r2(s$ff, taylor_1993(s$core_pce, s$output_gap)),
                  pre_zlb_1987_2008 = r2(greenspan$ff, taylor_1993(greenspan$core_pce, greenspan$output_gap)))
  static_full <- fit_taylor(s)
  static_gs <- fit_taylor(greenspan)
  inertial_q <- fit_inertial(s)
  inertial_m <- fit_inertial(monthly)
  ar_sel <- select_ar(s$ff)
  ar1_q <- fit_ar(s$ff, 1)
  ar1_m <- fit_ar(monthly$ff, 1)

  fc <- oos_forecasts(s, start = oos_start, p = ar_sel$best_p)
  okun <- fit_okun(d)
  macro <- scenario_macro(d)
  jo <- jump_off(d)
  paths <- project_rates(inertial_q, macro, jo$ff)
  paths$unemp_gap <- predict(okun, newdata = paths)
  paths$unrate <- paths$unemp_gap + (jo$unrate - jo$unemp_gap)   # CBO noncyclical rate held at its jump-off value
  ym <- fit_yield_models(d)
  sm <- fit_spread_model(d)
  mk <- scenario_markets(paths, d, ym, sm)

  list(
    data = d, sample = s, monthly = monthly, jump_off = jo,
    taylor_1993_r2 = taylor_fit, static_full = static_full, static_greenspan = static_gs,
    inertial = inertial_q, inertial_monthly = inertial_m, ar = ar_sel, ar1 = ar1_q, ar1_monthly = ar1_m,
    persistence = persistence_by_regime(s), rolling = rolling_coefficients(s),
    oos = fc, oos_summary = oos_summary(fc), regimes = regime_errors(s, inertial_q),
    deviations = policy_deviations(s), breaks = structural_breaks(s),
    okun = okun, macro = macro, paths = paths, yields = ym, spreads = sm, markets = mk,
    pnl = duration_pnl(mk, d)
  )
}
