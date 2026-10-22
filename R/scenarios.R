# Nine-quarter macro scenarios in the CCAR / DFAST layout (baseline plus alternative paths, quarterly,
# starting the quarter after the jump-off) and the policy-rate paths implied by the estimated rule.
#
# Scenario paths are ASSUMPTIONS. Each is defined by anchor values for core PCE inflation and the output gap
# at a few horizons; quarters in between are linearly interpolated from the jump-off quarter's actual values.

SCENARIOS <- list(
  baseline = list(
    label = "Baseline",
    narrative = "Inflation keeps easing toward target; growth runs close to potential.",
    core_pce = c(q2 = NA, q4 = 2.6, q9 = 2.2),
    output_gap = c(q2 = NA, q4 = -0.2, q9 = 0.0)
  ),
  hawkish = list(
    label = "Hawkish (inflation re-acceleration)",
    narrative = "Tariff and wage pass-through push core inflation back toward 4%; the economy overheats.",
    core_pce = c(q2 = 3.4, q4 = 4.0, q9 = 3.5),
    output_gap = c(q2 = 1.8, q4 = 2.0, q9 = 1.5)
  ),
  dovish = list(
    label = "Dovish (recession)",
    narrative = "Demand shock: a DFAST-style recession opens a 4% output gap and inflation undershoots.",
    core_pce = c(q2 = NA, q4 = 2.0, q9 = 1.6),
    output_gap = c(q2 = -2.5, q4 = -4.0, q9 = -2.5)
  )
)

HORIZON <- 9

anchor_path <- function(start_value, anchors, horizon = HORIZON) {
  q <- c(0, as.integer(sub("q", "", names(anchors))))
  v <- c(start_value, unname(anchors))
  keep <- !is.na(v)
  stats::approx(q[keep], v[keep], xout = seq_len(horizon), rule = 2)$y
}

scenario_macro <- function(d, scenarios = SCENARIOS, horizon = HORIZON) {
  last <- jump_off(d)
  dates <- seq(last$date, by = "quarter", length.out = horizon + 1)[-1]
  do.call(rbind, lapply(names(scenarios), function(s) {
    sc <- scenarios[[s]]
    data.frame(scenario = s, quarter = seq_len(horizon), date = dates,
               core_pce = anchor_path(last$core_pce, sc$core_pce, horizon),
               output_gap = anchor_path(last$output_gap, sc$output_gap, horizon))
  }))
}

# Iterate the inertial rule along each scenario. Residual bootstrap gives an 80% band; the policy rate is
# floored at the effective lower bound.
project_rates <- function(inertial, macro, jump_off_rate, n_boot = 2000, floor = 0.125, seed = 42) {
  b <- coef(inertial$model)
  res <- residuals(inertial$model)
  set.seed(seed)
  do.call(rbind, lapply(split(macro, macro$scenario), function(m) {
    m <- m[order(m$quarter), ]
    step <- function(prev, k, shock) max(floor, b[[1]] + b[["ff_lag"]] * prev + b[["core_pce"]] * m$core_pce[k] +
                                            b[["output_gap"]] * m$output_gap[k] + shock)
    central <- Reduce(function(prev, k) step(prev, k, 0), seq_len(nrow(m)), jump_off_rate, accumulate = TRUE)[-1]
    sims <- replicate(n_boot, {
      shocks <- sample(res, nrow(m), replace = TRUE)
      Reduce(function(prev, k) step(prev, k, shocks[k]), seq_len(nrow(m)), jump_off_rate, accumulate = TRUE)[-1]
    })
    cbind(m, ff = central, ff_p10 = apply(sims, 1, stats::quantile, 0.10), ff_p90 = apply(sims, 1, stats::quantile, 0.90),
          taylor_1993 = pmax(floor, taylor_1993(m$core_pce, m$output_gap)))
  }))
}

# Okun's law, estimated: unemployment gap on output gap. Used to report an unemployment path per scenario.
fit_okun <- function(d) {
  x <- d[!is.na(d$unemp_gap) & !is.na(d$output_gap), ]
  stats::lm(unemp_gap ~ output_gap, data = x)
}
