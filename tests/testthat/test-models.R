set.seed(1)

simulate_policy <- function(n = 300, rho = 0.8, b_pi = 1.5, b_y = 0.5, sd = 0.2) {
  infl <- 2 + stats::arima.sim(list(ar = 0.9), n, sd = 0.4)
  gap <- stats::arima.sim(list(ar = 0.8), n, sd = 0.6)
  ff <- numeric(n); ff[1] <- 3
  for (t in 2:n) ff[t] <- rho * ff[t - 1] + (1 - rho) * (0.5 + b_pi * infl[t] + b_y * gap[t]) + stats::rnorm(1, 0, sd)
  data.frame(date = seq(as.Date("1950-01-01"), by = "quarter", length.out = n), ff = ff,
             core_pce = as.numeric(infl), output_gap = as.numeric(gap), chair = factor("Test"))
}

test_that("Taylor (1993) prescription matches the textbook formula", {
  expect_equal(taylor_1993(2, 0), 4)                  # at target with no slack: r* + pi* = 4
  expect_equal(taylor_1993(4, -2), 2 + 4 + 1 - 1)     # 6
  expect_equal(taylor_balanced(2, -2), 2)
})

test_that("inertial rule recovers smoothing and long-run responses", {
  d <- simulate_policy(800)
  f <- fit_inertial(d)
  expect_equal(f$rho, 0.8, tolerance = 0.05)
  expect_equal(f$long_run["inflation", "estimate"], 1.5, tolerance = 0.25)
  expect_equal(f$long_run["output_gap", "estimate"], 0.5, tolerance = 0.25)
  expect_gt(f$r2, f$r2_changes)                       # level fit flatters the model
  expect_equal(f$half_life_quarters, log(0.5) / log(f$rho))
})

test_that("AR fit recovers persistence and selection uses a common sample", {
  y <- as.numeric(stats::arima.sim(list(ar = 0.9), 2000)) + 5
  a <- fit_ar(y, 1)
  expect_equal(a$persistence, 0.9, tolerance = 0.03)
  sel <- select_ar(y, max_p = 4)
  expect_equal(nrow(sel$table), 4)
  expect_true(sel$best_p %in% 1:4)
})

test_that("R-squared and RMSE helpers", {
  expect_equal(r2(c(1, 2, 3), c(1, 2, 3)), 1)
  expect_equal(r2(c(1, 2, 3), c(2, 2, 2)), 0)
  expect_equal(rmse(c(3, -4)), sqrt(12.5))
})

test_that("scenario anchors interpolate from the jump-off value", {
  expect_equal(anchor_path(3, c(q2 = NA, q4 = 2, q9 = 2), 9)[4], 2)
  expect_equal(anchor_path(3, c(q2 = NA, q4 = 2, q9 = 2), 9)[2], 2.5)
  expect_equal(anchor_path(1, c(q2 = 3, q4 = 3, q9 = 1), 9)[1], 2)
})

test_that("rate projection follows the rule and respects the lower bound", {
  d <- simulate_policy(400)
  f <- fit_inertial(d)
  macro <- data.frame(scenario = "s", quarter = 1:9, date = seq(as.Date("2030-01-01"), by = "quarter", length.out = 9),
                      core_pce = 2, output_gap = 0)
  p <- project_rates(f, macro, jump_off_rate = 4, n_boot = 200)
  b <- coef(f$model)
  expect_equal(p$ff[1], b[[1]] + b[["ff_lag"]] * 4 + 2 * b[["core_pce"]], tolerance = 1e-10)
  expect_true(all(p$ff_p10 <= p$ff & p$ff <= p$ff_p90))
  deep <- transform(macro, core_pce = -5, output_gap = -10)
  expect_true(all(project_rates(f, deep, 0.5, n_boot = 50)$ff >= 0.125))
})

test_that("duration P&L uses -D dy + 0.5 C dy^2", {
  d <- data.frame(date = as.Date("2026-04-01"), ff = 4, core_pce = 3, output_gap = 0, gs2 = 4, gs10 = 4.5, baa_spread = 2)
  mk <- data.frame(scenario = "s", quarter = 9, gs2 = 5, gs10 = 5.5, baa_spread = 3)
  pnl <- duration_pnl(mk, d)
  ten <- pnl[pnl$position == "10-year Treasury", ]
  expect_equal(ten$rate_pnl, 100e6 * (-8.1 * 0.01 + 0.5 * 75 * 0.01^2))
  corp <- pnl[pnl$position == "10-year Baa corporate", ]
  expect_equal(corp$spread_pnl, 100e6 * (-7.6 * 0.01))
  expect_equal(corp$change_spread_bp, 100)
})

test_that("deviation episodes need at least two consecutive quarters beyond the threshold", {
  d <- data.frame(date = seq(as.Date("2000-01-01"), by = "quarter", length.out = 6), core_pce = 2, output_gap = 0,
                  ff = c(4, 1, 1, 4, 7, 4))                 # rule says 4
  ep <- policy_deviations(d, threshold = 2)
  expect_equal(nrow(ep), 1)
  expect_equal(ep$direction, "looser than rule")
  expect_equal(ep$quarters, 2)
})

test_that("quarter labels and chair assignment", {
  expect_equal(qlabel(as.Date(c("2026-04-01", "1987-10-01"))), c("2026Q2", "1987Q4"))
  expect_equal(as.character(fed_chair(as.Date(c("1980-01-01", "2020-01-01")))), c("Volcker", "Powell"))
})
