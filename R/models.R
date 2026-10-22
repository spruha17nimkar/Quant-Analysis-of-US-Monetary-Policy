# Policy-rate models: Taylor (1993) rule, estimated Taylor rules, the inertial (partial-adjustment) Taylor
# rule and autoregressive models of the federal funds rate.

# Taylor (1993): i = r* + pi + 0.5 (pi - pi*) + 0.5 gap, with r* = pi* = 2.
taylor_1993 <- function(inflation, gap, r_star = 2, pi_star = 2, a_pi = 0.5, a_y = 0.5) {
  r_star + inflation + a_pi * (inflation - pi_star) + a_y * gap
}

# Balanced-approach rule (Yellen 2012): output-gap weight 1.0.
taylor_balanced <- function(inflation, gap, r_star = 2, pi_star = 2) taylor_1993(inflation, gap, r_star, pi_star, 0.5, 1.0)

nw_coefs <- function(fit, lag = 4) {
  V <- sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)
  ct <- lmtest::coeftest(fit, vcov. = V)
  data.frame(term = rownames(ct), estimate = ct[, 1], std_error = ct[, 2], t_value = ct[, 3], p_value = ct[, 4],
             row.names = NULL)
}

r2 <- function(actual, fitted) {
  ok <- !is.na(actual) & !is.na(fitted)
  1 - sum((actual[ok] - fitted[ok])^2) / sum((actual[ok] - mean(actual[ok]))^2)
}

rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))

# Static estimated rule: i_t = a + b_pi pi_t + b_y gap_t + e_t
fit_taylor <- function(d) {
  fit <- stats::lm(ff ~ core_pce + output_gap, data = d)
  list(model = fit, coefs = nw_coefs(fit), r2 = summary(fit)$r.squared, n = nobs(fit),
       sample = range(d$date), taylor_principle = unname(coef(fit)["core_pce"]) > 1)
}

# Inertial rule: i_t = rho i_{t-1} + (1 - rho)(a + b_pi pi_t + b_y gap_t) + e_t, estimated in reduced form
# i_t = c + rho i_{t-1} + g_pi pi_t + g_y gap_t, with long-run responses b = g / (1 - rho) (delta-method s.e.).
fit_inertial <- function(d) {
  d$ff_lag <- lag_vec(d$ff)
  d <- d[!is.na(d$ff_lag), ]
  fit <- stats::lm(ff ~ ff_lag + core_pce + output_gap, data = d)
  b <- coef(fit)
  V <- sandwich::NeweyWest(fit, lag = 4, prewhite = FALSE)
  rho <- b[["ff_lag"]]
  lr <- function(name) {
    est <- b[[name]] / (1 - rho)
    grad <- setNames(rep(0, length(b)), names(b))
    grad[name] <- 1 / (1 - rho)
    grad["ff_lag"] <- b[[name]] / (1 - rho)^2
    c(estimate = est, std_error = sqrt(drop(t(grad) %*% V %*% grad)))
  }
  long_run <- rbind(inflation = lr("core_pce"), output_gap = lr("output_gap"), intercept = lr("(Intercept)"))
  list(model = fit, coefs = nw_coefs(fit), r2 = summary(fit)$r.squared, r2_changes = r2(d$ff - d$ff_lag, fitted(fit) - d$ff_lag),
       rho = rho, long_run = long_run, n = nobs(fit), sample = range(d$date), data = d,
       half_life_quarters = log(0.5) / log(rho))
}

# AR(p) on the level of the funds rate by OLS (so R^2 is comparable with the rules).
fit_ar <- function(y, p) {
  X <- sapply(seq_len(p), function(k) lag_vec(y, k))
  colnames(X) <- paste0("lag", seq_len(p))
  dd <- data.frame(y = y, X)
  fit <- stats::lm(y ~ ., data = dd)
  phi <- coef(fit)[-1]
  list(model = fit, p = p, phi = phi, intercept = coef(fit)[[1]], r2 = summary(fit)$r.squared,
       aic = AIC(fit), bic = BIC(fit), persistence = sum(phi),
       half_life_quarters = if (sum(phi) > 0 && sum(phi) < 1) log(0.5) / log(sum(phi)) else Inf,
       sigma = summary(fit)$sigma)
}

select_ar <- function(y, max_p = 8) {
  # Information criteria are compared on a common sample (the first max_p observations dropped for every p).
  X <- sapply(seq_len(max_p), function(k) lag_vec(y, k))
  keep <- seq(max_p + 1, length(y))
  tab <- do.call(rbind, lapply(seq_len(max_p), function(p) {
    f <- stats::lm(y[keep] ~ X[keep, seq_len(p), drop = FALSE])
    data.frame(p = p, aic = AIC(f), bic = BIC(f), r2 = summary(f)$r.squared, persistence = sum(coef(f)[-1]))
  }))
  best_p <- tab$p[which.min(tab$bic)]
  list(table = tab, best_p = best_p, best = fit_ar(y, best_p))
}

# AR(1) persistence by Fed chair / economic regime.
persistence_by_regime <- function(d) {
  regimes <- split(d, d$chair, drop = TRUE)
  rows <- lapply(names(regimes), function(n) {
    x <- regimes[[n]]
    if (nrow(x) < 12) return(NULL)
    f <- fit_ar(x$ff, 1)
    ci <- stats::confint(f$model)["lag1", ]
    data.frame(regime = n, start = qlabel(min(x$date)), end = qlabel(max(x$date)), quarters = nrow(x),
               mean_rate = mean(x$ff), sd_quarterly_change = stats::sd(diff(x$ff)), rho = f$persistence,
               rho_low = ci[[1]], rho_high = ci[[2]], half_life = f$half_life_quarters, row.names = NULL)
  })
  do.call(rbind, rows)
}

rolling_coefficients <- function(d, window = 40) {
  idx <- seq(window, nrow(d))
  do.call(rbind, lapply(idx, function(i) {
    w <- d[(i - window + 1):i, ]
    f <- stats::lm(ff ~ core_pce + output_gap, data = w)
    data.frame(date = d$date[i], b_inflation = coef(f)[["core_pce"]], b_gap = coef(f)[["output_gap"]],
               r2 = summary(f)$r.squared)
  }))
}
