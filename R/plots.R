# ggplot2 figures for the report.

THEME <- ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(legend.position = "bottom", plot.title = ggplot2::element_text(face = "bold", size = 12),
                 panel.grid.minor = ggplot2::element_blank())
COLS <- c(Actual = "black", "Taylor (1993)" = "#e67e22", "Estimated rule" = "#2e86c1", "Inertial rule (fitted)" = "#c0392b",
          baseline = "#2c3e50", hawkish = "#c0392b", dovish = "#2e86c1")

save_plot <- function(p, file, w = 9, h = 4.8) ggplot2::ggsave(file, p, width = w, height = h, dpi = 150, bg = "white")

recession_bands <- function(d) {
  # Quarters where the output gap fell by more than 1.5 points from its trailing 4-quarter peak are shaded
  # as downturns (a data-driven stand-in for NBER dates, which FRED does not provide at quarterly frequency here).
  peak <- zoo::rollapplyr(d$output_gap, 4, max, fill = NA)
  r <- !is.na(peak) & (peak - d$output_gap) > 1.5
  runs <- rle(r)
  ends <- cumsum(runs$lengths); starts <- ends - runs$lengths + 1
  k <- which(runs$values)
  data.frame(xmin = d$date[starts[k]], xmax = d$date[ends[k]] + 90)
}

plot_rules <- function(s, inertial, static_fit) {
  df <- rbind(
    data.frame(date = s$date, value = s$ff, series = "Actual"),
    data.frame(date = s$date, value = taylor_1993(s$core_pce, s$output_gap), series = "Taylor (1993)"),
    data.frame(date = s$date, value = fitted(static_fit$model), series = "Estimated rule"),
    data.frame(date = inertial$data$date, value = fitted(inertial$model), series = "Inertial rule (fitted)")
  )
  ggplot2::ggplot(df, ggplot2::aes(date, value, colour = series)) +
    ggplot2::geom_rect(data = recession_bands(s), inherit.aes = FALSE,
                       ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf), fill = "grey85", alpha = 0.6) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::scale_colour_manual(values = COLS, name = NULL) +
    ggplot2::labs(title = "Federal funds rate vs policy rules", x = NULL, y = "percent") + THEME
}

plot_deviation <- function(s) {
  s$deviation <- s$ff - taylor_1993(s$core_pce, s$output_gap)
  ggplot2::ggplot(s, ggplot2::aes(date, deviation, fill = deviation > 0)) +
    ggplot2::geom_col(width = 80) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = "#c0392b", `FALSE` = "#2e86c1"), labels = c("looser than rule", "tighter than rule"), name = NULL) +
    ggplot2::geom_hline(yintercept = c(-2, 2), linetype = "dashed", linewidth = 0.3) +
    ggplot2::labs(title = "Discretion: actual funds rate minus Taylor (1993) prescription", x = NULL, y = "percentage points") + THEME
}

plot_rolling <- function(roll) {
  df <- rbind(data.frame(date = roll$date, value = roll$b_inflation, coef = "Inflation response"),
              data.frame(date = roll$date, value = roll$b_gap, coef = "Output-gap response"))
  ggplot2::ggplot(df, ggplot2::aes(date, value, colour = coef)) +
    ggplot2::geom_hline(yintercept = c(0, 1), linetype = c("solid", "dashed"), linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::annotate("text", x = min(df$date), y = 1.1, label = "Taylor principle (1.0)", hjust = 0, size = 3) +
    ggplot2::scale_colour_manual(values = c("#c0392b", "#2e86c1"), name = NULL) +
    ggplot2::labs(title = "Rolling 10-year estimated Taylor-rule coefficients", x = "end of window", y = "coefficient") + THEME
}

plot_scenarios <- function(s, paths) {
  hist <- tail(s[, c("date", "ff")], 16)
  p1 <- ggplot2::ggplot(paths, ggplot2::aes(date, ff, colour = scenario, fill = scenario)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = ff_p10, ymax = ff_p90), alpha = 0.12, colour = NA) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_line(ggplot2::aes(y = taylor_1993), linetype = "dotted", linewidth = 0.6) +
    ggplot2::geom_line(data = hist, ggplot2::aes(date, ff), inherit.aes = FALSE, linewidth = 1) +
    ggplot2::scale_colour_manual(values = COLS) + ggplot2::scale_fill_manual(values = COLS) +
    ggplot2::labs(title = "Policy-rate paths (solid: inertial rule, band: 80%; dotted: Taylor 1993)", x = NULL, y = "percent",
                  colour = NULL, fill = NULL) + THEME
  long <- rbind(data.frame(date = paths$date, scenario = paths$scenario, value = paths$core_pce, var = "Core PCE inflation, % y/y"),
                data.frame(date = paths$date, scenario = paths$scenario, value = paths$output_gap, var = "Output gap, % of potential"))
  p2 <- ggplot2::ggplot(long, ggplot2::aes(date, value, colour = scenario)) + ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::facet_wrap(~var, scales = "free_y") + ggplot2::scale_colour_manual(values = COLS) +
    ggplot2::labs(title = "Scenario macro paths (assumptions)", x = NULL, y = NULL, colour = NULL) + THEME
  patchwork::wrap_plots(p2, p1, ncol = 1, heights = c(1, 1.3))
}

plot_markets <- function(mk) {
  long <- rbind(data.frame(date = mk$date, scenario = mk$scenario, value = mk$gs2, var = "2-year Treasury"),
                data.frame(date = mk$date, scenario = mk$scenario, value = mk$gs10, var = "10-year Treasury"),
                data.frame(date = mk$date, scenario = mk$scenario, value = mk$baa_spread, var = "Baa - 10y spread"))
  ggplot2::ggplot(long, ggplot2::aes(date, value, colour = scenario)) + ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::facet_wrap(~var, scales = "free_y") + ggplot2::scale_colour_manual(values = COLS) +
    ggplot2::labs(title = "Market variables implied by each policy path", x = NULL, y = "percent", colour = NULL) + THEME
}

plot_oos <- function(fc) {
  x <- fc[fc$h == 4, ]
  df <- rbind(data.frame(date = x$target, value = x$actual, series = "Actual"),
              data.frame(date = x$target, value = x$random_walk, series = "Random walk"),
              data.frame(date = x$target, value = x$ar, series = "AR"),
              data.frame(date = x$target, value = x$inertial_taylor, series = "Inertial rule"))
  ggplot2::ggplot(df, ggplot2::aes(date, value, colour = series)) + ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::scale_colour_manual(values = c(Actual = "black", "Random walk" = "grey60", AR = "#2e86c1", "Inertial rule" = "#c0392b"), name = NULL) +
    ggplot2::labs(title = "Out-of-sample 4-quarter-ahead forecasts (expanding window)", x = NULL, y = "percent") + THEME
}
