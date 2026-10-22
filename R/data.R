# Data layer: FRED downloads (no API key needed), on-disk cache, quarterly aggregation and derived gaps.

FRED_SERIES <- c(
  FEDFUNDS = "Effective federal funds rate, % (monthly)",
  PCEPILFE = "Core PCE price index (monthly)",
  PCEPI    = "Headline PCE price index (monthly)",
  CPIAUCSL = "CPI-U, all items (monthly)",
  GDPC1    = "Real GDP, chained 2017 $bn (quarterly)",
  GDPPOT   = "CBO real potential GDP (quarterly)",
  UNRATE   = "Unemployment rate, % (monthly)",
  NROU     = "CBO noncyclical rate of unemployment (quarterly)",
  TB3MS    = "3-month Treasury bill, % (monthly)",
  GS2      = "2-year Treasury constant maturity, % (monthly)",
  GS10     = "10-year Treasury constant maturity, % (monthly)",
  BAA10YM  = "Moody's Baa corporate yield minus 10-year Treasury, % (monthly)",
  AAA10YM  = "Moody's Aaa corporate yield minus 10-year Treasury, % (monthly)"
)

fred_get <- function(id, cache_dir = "data/raw", refresh = FALSE) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache_dir, paste0(id, ".csv"))
  if (refresh || !file.exists(path)) {
    url <- sprintf("https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s", id)
    utils::download.file(url, path, quiet = TRUE, mode = "wb")
  }
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  names(raw) <- c("date", "value")
  raw$date <- as.Date(raw$date)
  raw$value <- suppressWarnings(as.numeric(raw$value))   # FRED marks missing values with "."
  raw[!is.na(raw$value), ]
}

quarter_start <- function(d) {
  m <- as.integer(format(d, "%m"))
  as.Date(sprintf("%s-%02d-01", format(d, "%Y"), 3 * ((m - 1) %/% 3) + 1))
}

yoy <- function(index, lag = 4) 100 * (index / c(rep(NA, lag), head(index, -lag)) - 1)

fed_chair <- function(d) {
  cut(d, breaks = as.Date(c("1951-04-02", "1970-02-01", "1978-03-08", "1979-08-06", "1987-08-11",
                            "2006-02-01", "2014-02-03", "2018-02-05", "2100-01-01")),
      labels = c("Martin", "Burns", "Miller", "Volcker", "Greenspan", "Bernanke", "Yellen", "Powell"),
      right = FALSE)
}

# One row per quarter. Monthly series are averaged; inflation is year-over-year; the output gap uses CBO
# potential GDP and the unemployment gap uses the CBO noncyclical rate.
build_dataset <- function(cache_dir = "data/raw", refresh = FALSE) {
  monthly <- c("FEDFUNDS", "PCEPILFE", "PCEPI", "CPIAUCSL", "UNRATE", "TB3MS", "GS2", "GS10", "BAA10YM", "AAA10YM")
  quarterly <- c("GDPC1", "GDPPOT", "NROU")
  series <- lapply(c(monthly, quarterly), fred_get, cache_dir = cache_dir, refresh = refresh)
  names(series) <- c(monthly, quarterly)

  q <- lapply(names(series), function(id) {
    s <- series[[id]]
    if (id %in% monthly) {
      qs <- quarter_start(s$date)
      v <- tapply(s$value, qs, mean)
      n <- tapply(s$value, qs, length)
      v <- v[n == 3]
      data.frame(date = as.Date(names(v)), value = as.numeric(v))
    } else {
      data.frame(date = s$date, value = s$value)
    }
  })
  names(q) <- names(series)
  dates <- sort(Reduce(union, lapply(q, function(z) as.character(z$date))))
  df <- data.frame(date = as.Date(dates))
  for (id in names(q)) df[[id]] <- q[[id]]$value[match(df$date, q[[id]]$date)]

  out <- data.frame(
    date = df$date,
    ff = df$FEDFUNDS,
    core_pce = yoy(df$PCEPILFE),
    pce = yoy(df$PCEPI),
    cpi = yoy(df$CPIAUCSL),
    output_gap = 100 * (df$GDPC1 - df$GDPPOT) / df$GDPPOT,
    unemp_gap = df$UNRATE - df$NROU,
    unrate = df$UNRATE,
    tb3 = df$TB3MS, gs2 = df$GS2, gs10 = df$GS10,
    baa_spread = df$BAA10YM, aaa_spread = df$AAA10YM
  )
  out$chair <- fed_chair(out$date)
  out$zlb <- !is.na(out$ff) & out$ff < 0.25
  out$high_inflation <- !is.na(out$core_pce) & out$core_pce > 4
  out <- out[out$date >= as.Date("1960-01-01") & out$date <= max(out$date[!is.na(out$ff)]), ]
  rownames(out) <- NULL
  out
}

# Rows usable for policy-rule estimation: rate, inflation and gap all observed.
model_sample <- function(d, start = "1965-01-01", end = NULL) {
  keep <- !is.na(d$ff) & !is.na(d$core_pce) & !is.na(d$output_gap) & d$date >= as.Date(start)
  if (!is.null(end)) keep <- keep & d$date <= as.Date(end)
  d[keep, ]
}

# The scenario jump-off: the last quarter with the funds rate, inflation and the output gap all observed.
jump_off <- function(d) d[max(which(!is.na(d$ff) & !is.na(d$core_pce) & !is.na(d$output_gap))), ]

lag_vec <- function(x, k = 1) c(rep(NA, k), head(x, -k))

qlabel <- function(d) paste0(format(d, "%Y"), "Q", (as.integer(format(d, "%m")) - 1) %/% 3 + 1)

# Monthly panel for the high-frequency version of the rules: funds rate and core PCE inflation are monthly;
# the quarterly output gap is interpolated linearly between mid-quarter points.
build_monthly <- function(cache_dir = "data/raw", refresh = FALSE) {
  ff <- fred_get("FEDFUNDS", cache_dir, refresh)
  pc <- fred_get("PCEPILFE", cache_dir, refresh)
  gdp <- fred_get("GDPC1", cache_dir, refresh)
  pot <- fred_get("GDPPOT", cache_dir, refresh)
  m <- data.frame(date = ff$date, ff = ff$value)
  m$core_pce <- yoy(pc$value[match(m$date, pc$date)], lag = 12)
  pot_v <- pot$value[match(gdp$date, pot$date)]
  gap <- 100 * (gdp$value - pot_v) / pot_v
  m$output_gap <- stats::approx(as.numeric(gdp$date) + 45, gap, xout = as.numeric(m$date), rule = 1)$y
  m$chair <- fed_chair(m$date)
  m[stats::complete.cases(m[, c("ff", "core_pce", "output_gap")]) & m$date >= as.Date("1965-01-01"), ]
}
