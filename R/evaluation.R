# Out-of-sample evaluation and model-limitation diagnostics.

# Expanding-window, pseudo out-of-sample forecasts made each quarter from `start` onward.
#   random walk      i_{t+h} = i_t
#   AR(p)            iterated h steps
#   inertial Taylor  iterated h steps using the macro data actually realised (a conditional forecast: it shows
#                    how good the rule is *given* the macro path, which is how it is used in scenario analysis)
oos_forecasts <- function(d, start = "2000-01-01", horizons = c(1, 4), p = 2) {
  origins <- which(d$date >= as.Date(start))
  out <- list()
  for (t in origins) {
    train <- d[seq_len(t), ]
    ar <- fit_ar(train$ff, p)
    inert <- stats::lm(ff ~ ff_lag + core_pce + output_gap, data = transform(train, ff_lag = lag_vec(ff)))
    for (h in horizons) {
      if (t + h > nrow(d)) next
      path_ar <- c(rev(tail(train$ff, p)))
      for (s in seq_len(h)) path_ar <- c(ar$intercept + sum(ar$phi * path_ar[seq_len(p)]), path_ar)
      prev <- train$ff[t]
      for (s in seq_len(h)) {
        prev <- coef(inert)[[1]] + coef(inert)[["ff_lag"]] * prev +
          coef(inert)[["core_pce"]] * d$core_pce[t + s] + coef(inert)[["output_gap"]] * d$output_gap[t + s]
      }
      out[[length(out) + 1]] <- data.frame(origin = d$date[t], target = d$date[t + h], h = h, actual = d$ff[t + h],
                                           random_walk = d$ff[t], ar = path_ar[1], inertial_taylor = prev)
    }
  }
  do.call(rbind, out)
}

oos_summary <- function(fc) {
  do.call(rbind, lapply(split(fc, fc$h), function(x) {
    data.frame(h = x$h[1], n = nrow(x),
               rmse_random_walk = rmse(x$actual - x$random_walk), rmse_ar = rmse(x$actual - x$ar),
               rmse_inertial_taylor = rmse(x$actual - x$inertial_taylor),
               oos_r2_levels_inertial = r2(x$actual, x$inertial_taylor),
               oos_r2_changes_inertial = r2(x$actual - x$random_walk, x$inertial_taylor - x$random_walk))
  }))
}

# Fit quality by macro regime: how badly the rules miss when inflation is high or the economy is volatile.
regime_errors <- function(d, inertial) {
  d$taylor_1993 <- taylor_1993(d$core_pce, d$output_gap)
  d$gap_1993 <- d$ff - d$taylor_1993
  e_in <- rep(NA_real_, nrow(d))
  e_in[match(inertial$data$date, d$date)] <- residuals(inertial$model)
  d$resid_inertial <- e_in
  vol <- c(NA, diff(d$output_gap))
  d$volatile <- abs(vol) > stats::quantile(abs(vol), 0.9, na.rm = TRUE)
  groups <- list(
    "All quarters" = rep(TRUE, nrow(d)),
    "Core PCE inflation > 4%" = d$high_inflation,
    "Core PCE inflation <= 4%" = !d$high_inflation,
    "1970s Great Inflation (1965-1979Q2)" = d$date < as.Date("1979-07-01"),
    "Volcker disinflation (1979Q3-1987Q2)" = d$date >= as.Date("1979-07-01") & d$date < as.Date("1987-07-01"),
    "Great Moderation (1987Q3-2007Q4)" = d$date >= as.Date("1987-07-01") & d$date < as.Date("2008-01-01"),
    "Zero lower bound quarters" = d$zlb,
    "2021-2023 inflation surge" = d$date >= as.Date("2021-01-01") & d$date < as.Date("2024-01-01"),
    "Top-decile output-gap swings" = d$volatile %in% TRUE
  )
  do.call(rbind, lapply(names(groups), function(g) {
    m <- groups[[g]]
    data.frame(regime = g, quarters = sum(m), rmse_taylor_1993 = rmse(d$gap_1993[m]),
               mean_gap_taylor_1993 = mean(d$gap_1993[m], na.rm = TRUE), rmse_inertial = rmse(d$resid_inertial[m]),
               max_abs_inertial = max(abs(d$resid_inertial[m]), na.rm = TRUE))
  }))
}

# Quarters where the Fed deviated most from the systematic rule (actual minus Taylor 1993 prescription).
policy_deviations <- function(d, threshold = 2) {
  d$prescribed <- taylor_1993(d$core_pce, d$output_gap)
  d$deviation <- d$ff - d$prescribed
  runs <- rle(sign(d$deviation) * (abs(d$deviation) > threshold))
  ends <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1
  ep <- which(runs$values != 0 & runs$lengths >= 2)
  do.call(rbind, lapply(ep, function(k) {
    x <- d[starts[k]:ends[k], ]
    data.frame(start = qlabel(x$date[1]), end = qlabel(x$date[nrow(x)]), quarters = nrow(x),
               direction = ifelse(runs$values[k] > 0, "tighter than rule", "looser than rule"),
               mean_deviation = mean(x$deviation), max_abs_deviation = max(abs(x$deviation)),
               mean_inflation = mean(x$core_pce), mean_output_gap = mean(x$output_gap))
  }))
}

structural_breaks <- function(d, h = 0.15) {
  bp <- strucchange::breakpoints(ff ~ core_pce + output_gap, data = d, h = h)
  n_breaks <- length(stats::na.omit(bp$breakpoints))
  dates <- if (n_breaks) d$date[bp$breakpoints] else as.Date(character(0))
  fs <- strucchange::Fstats(ff ~ core_pce + output_gap, data = d, from = h)
  list(breakpoints = dates, n_breaks = n_breaks, sup_f = unname(fs$Fstats[which.max(fs$Fstats)]),
       sup_f_p = strucchange::sctest(fs)$p.value, sup_f_date = d$date[fs$breakpoint])
}
