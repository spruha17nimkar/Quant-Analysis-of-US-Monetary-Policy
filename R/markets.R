# From policy-rate expectations to market and credit risk: Treasury yields, duration risk and credit spreads.

# Expectations regressions: a Treasury yield on the average realised funds rate over the next `k` quarters
# (a perfect-foresight proxy for the expected policy path) plus core inflation for the term premium / inflation
# risk component. Estimated on 1987Q3 onward, where the policy framework is comparable.
fit_yield_models <- function(d, start = "1987-07-01", k = 8) {
  d <- d[d$date >= as.Date(start), ]
  fwd <- sapply(seq_len(nrow(d)), function(i) if (i + k - 1 <= nrow(d)) mean(d$ff[i:(i + k - 1)]) else NA)
  d$exp_path <- fwd
  out <- list()
  for (y in c("gs2", "gs10")) {
    x <- d[!is.na(d[[y]]) & !is.na(d$exp_path) & !is.na(d$core_pce), ]
    f <- stats::lm(stats::as.formula(paste(y, "~ exp_path + core_pce")), data = x)
    out[[y]] <- list(model = f, coefs = nw_coefs(f, lag = k), r2 = summary(f)$r.squared, n = nobs(f))
  }
  # Short-run pass-through: quarterly yield changes on funds-rate changes.
  dd <- data.frame(dff = diff(d$ff), dgs2 = diff(d$gs2), dgs10 = diff(d$gs10), dslope = diff(d$gs10 - d$gs2))
  out$pass_through <- do.call(rbind, lapply(c("dgs2", "dgs10", "dslope"), function(v) {
    f <- stats::lm(stats::as.formula(paste(v, "~ dff")), data = dd)
    data.frame(series = v, beta = coef(f)[["dff"]], se = nw_coefs(f)$std_error[2], r2 = summary(f)$r.squared)
  }))
  out
}

SPREAD_SPECS <- list(
  level_gap = baa_spread ~ spread_lag + output_gap + dff,
  gap_momentum = baa_spread ~ spread_lag + d_gap + output_gap + dff,
  unemployment = baa_spread ~ spread_lag + d_gap + unemp_gap,
  policy_stance = baa_spread ~ spread_lag + d_gap + unemp_gap + stance,
  curve_slope = baa_spread ~ spread_lag + d_gap + unemp_gap + slope
)

spread_inputs <- function(x) {
  x$spread_lag <- lag_vec(x$baa_spread)
  x$dff <- c(NA, diff(x$ff))
  x$d_gap <- c(NA, diff(x$output_gap))
  x$stance <- x$ff - x$core_pce
  x$slope <- x$gs10 - x$ff
  x
}

# Baa-Treasury spread. Candidate specifications are compared and the lowest-BIC one is used; the comparison is
# kept as part of the model documentation.
fit_spread_model <- function(d, start = "1987-07-01", specs = SPREAD_SPECS) {
  x <- spread_inputs(d[d$date >= as.Date(start), ])
  vars <- unique(unlist(lapply(specs, all.vars)))
  x <- x[stats::complete.cases(x[, vars]), ]
  fits <- lapply(specs, stats::lm, data = x)
  comparison <- do.call(rbind, lapply(names(fits), function(n) {
    ct <- nw_coefs(fits[[n]])
    data.frame(spec = n, formula = deparse(specs[[n]]), r2 = summary(fits[[n]])$r.squared, bic = BIC(fits[[n]]),
               terms = paste(sprintf("%s %.3f (t %.1f)", ct$term[-1], ct$estimate[-1], ct$t_value[-1]), collapse = "; "))
  }))
  best <- comparison$spec[which.min(comparison$bic)]
  f <- fits[[best]]
  list(model = f, spec = best, coefs = nw_coefs(f), r2 = summary(f)$r.squared, n = nobs(f), comparison = comparison)
}

# Yields and spreads along each scenario's rate path. The 8-quarter-ahead expected path beyond the scenario
# horizon is held at the last projected rate.
scenario_markets <- function(paths, d, ym, sm) {
  last <- jump_off(d)
  expected <- function(ff) {
    ext <- c(ff, rep(tail(ff, 1), 8))
    sapply(seq_along(ff), function(i) mean(ext[i:(i + 7)]))
  }
  # Jump-off yields are assumed to price the baseline path, so every scenario shares the same anchor.
  base <- paths[paths$scenario == "baseline", ]
  base <- base[order(base$quarter), ]
  jump <- data.frame(exp_path = mean(c(last$ff, base$ff[1:7])), core_pce = last$core_pce)
  do.call(rbind, lapply(split(paths, paths$scenario), function(p) {
    p <- p[order(p$quarter), ]
    p$exp_path <- expected(p$ff)
    p$gs2 <- predict(ym$gs2$model, newdata = p)
    p$gs10 <- predict(ym$gs10$model, newdata = p)
    # Apply model-implied changes relative to the jump-off to the last observed yields.
    p$gs2 <- last$gs2 + p$gs2 - predict(ym$gs2$model, newdata = jump)
    p$gs10 <- last$gs10 + p$gs10 - predict(ym$gs10$model, newdata = jump)
    s <- last$baa_spread
    prev <- last
    p$baa_spread <- NA
    for (k in seq_len(nrow(p))) {
      row <- data.frame(spread_lag = s, output_gap = p$output_gap[k], d_gap = p$output_gap[k] - prev$output_gap,
                        dff = p$ff[k] - prev$ff, unemp_gap = p$unemp_gap[k], stance = p$ff[k] - p$core_pce[k],
                        slope = p$gs10[k] - p$ff[k])
      s <- unname(predict(sm$model, newdata = row))
      p$baa_spread[k] <- s
      prev <- list(output_gap = p$output_gap[k], ff = p$ff[k])
    }
    p$baa_yield <- p$gs10 + p$baa_spread
    p
  }))
}

# Price impact on a $100mm-per-position portfolio at the end of the horizon (price return only, no carry):
#   dP/P ~ -D dy + 0.5 C dy^2, with spread duration applied to the credit spread change.
PORTFOLIO <- data.frame(
  position = c("2-year Treasury", "10-year Treasury", "10-year Baa corporate"),
  notional = 100e6, duration = c(1.9, 8.1, 7.6), convexity = c(4.5, 75, 68),
  rate = c("gs2", "gs10", "gs10"), spread = c(NA, NA, "baa_spread")
)

duration_pnl <- function(markets, d, portfolio = PORTFOLIO) {
  last <- jump_off(d)
  do.call(rbind, lapply(split(markets, markets$scenario), function(m) {
    end <- m[which.max(m$quarter), ]
    do.call(rbind, lapply(seq_len(nrow(portfolio)), function(i) {
      pos <- portfolio[i, ]
      dy <- (end[[pos$rate]] - last[[pos$rate]]) / 100
      ds <- if (is.na(pos$spread)) 0 else (end[[pos$spread]] - last[[pos$spread]]) / 100
      rate_pnl <- pos$notional * (-pos$duration * dy + 0.5 * pos$convexity * dy^2)
      spread_pnl <- if (is.na(pos$spread)) 0 else pos$notional * (-pos$duration * ds)
      data.frame(scenario = m$scenario[1], position = pos$position, change_rate_bp = 100 * 100 * dy,
                 change_spread_bp = 100 * 100 * ds, rate_pnl = rate_pnl, spread_pnl = spread_pnl,
                 total_pnl = rate_pnl + spread_pnl, dv01 = pos$notional * pos$duration * 1e-4)
    }))
  }))
}
