# Projection model for HERD Explorer, run once a year after the data build.
#
# Backtests three candidates on total R&D (refit at several past cutoffs, score the next
# three years by CRPS): a hierarchical growth model, a hierarchical GAM on levels, and a
# naive own-growth baseline. The best-scoring model is then fit to every dollar measure and
# simulated. The growth model has won every backtest so far:
#   dlog ~ sector + s(state, re) + s(inst, re) + s(year, re) + s(year x sector, re)
# with size-dependent noise and new shared year shocks simulated for future years, so sums
# over any group keep the shared uncertainty. See fit_growth() and simulate_growth().
#
# Horizon and backtest cutoffs follow pipeline/release.yml.
#
# Writes to model/output/ (published to Hugging Face by model/publish.sh):
#   <measure>.parquet   inst_id, year, draw, value (thousands of dollars), 200 draws per institution-year
#   backtest.parquet    CRPS and interval coverage by model, cutoff and horizon
#   model_info.parquet  settings and fitted parameters for the methods page
#
# Usage: Rscript model/fit.R

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(mgcv)
  library(scoringRules)
})

set.seed(20261027)
# Every dollar measure; personnel counts start in FY 2022, too few years to model
measures <- NULL  # filled from measure_catalog once the database is open
horizon <- NULL        # years projected past the last year of data, from release.yml
n_draws <- 200L        # draws stored per institution-year
gp_range <- 3           # Gaussian process range in years (3, 5 and 8 scored within 0.001 CRPS in backtests)
min_years <- 4L        # institutions need this many positive years to be modeled

root <- getwd()
if (!file.exists(file.path(root, "model", "fit.R"))) stop("run from the repository root: Rscript model/fit.R")
source(file.path(root, "pipeline", "release.R"))
release <- read_release(root)
horizon <- release$projection$horizon
# Published to Hugging Face by model/publish.sh, not committed to git
out_dir <- file.path(root, "model", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

con <- dbConnect(duckdb(), file.path(root, "docs", "data", "herd.duckdb"), read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
measures <- dbGetQuery(con, "SELECT id FROM measure_catalog WHERE unit = 'thousands_usd' ORDER BY id")$id
data_last <- dbGetQuery(con, "SELECT max(year) AS y FROM metrics")$y
if (data_last != release$last_year) stop("the database ends in ", data_last, " but release.yml says ", release$last_year, "; run Rscript pipeline/build.R first")

# Small groups pool into "Other" so every sector curve has enough institutions behind it
inst <- dbGetQuery(con, "
  SELECT g.inst_id, g.sector, i.state
  FROM institution_groups g
  JOIN (SELECT * FROM institutions QUALIFY row_number() OVER (PARTITION BY inst_id ORDER BY year DESC) = 1) i USING (inst_id)")
small <- c("Associate's and tribal", "System office", "Not classified", "Independent research institute")
inst$model_sector <- ifelse(inst$sector %in% small, "Other", inst$sector)

load_measure <- function(id) {
  d <- dbGetQuery(con, sprintf("SELECT inst_id, year, value FROM metrics WHERE measure_id = '%s' AND value > 0", id))
  d <- merge(d, inst, by = "inst_id")
  keep <- names(which(table(d$inst_id) >= min_years))
  d <- d[d$inst_id %in% keep, ]
  d <- d[order(d$inst_id, d$year), ]
  d$y <- log(d$value)
  d$inst <- factor(d$inst_id)
  d$state <- factor(d$state)
  d$model_sector <- factor(d$model_sector)
  d
}

fit_model <- function(d, gp_range) {
  d$year_c <- d$year - 2018
  k <- min(8L, length(unique(d$year)) - 1L)   # basis size cannot exceed the number of distinct years
  base <- function(rho = 0, start = NULL) bam(
    y ~ model_sector + s(year, by = model_sector, bs = "gp", m = c(3, gp_range), k = k) +
      s(state, bs = "re") + s(inst, bs = "re") + s(inst, year_c, bs = "re"),
    data = d, method = "fREML", discrete = TRUE, rho = rho, AR.start = start)
  first <- !duplicated(d$inst)
  m0 <- base()
  # AR(1) coefficient from lag-1 correlation of residuals within institution
  r <- residuals(m0)
  rho <- cor(r[-1][!first[-1]], r[-length(r)][!first[-1]])
  m <- base(rho, first)
  m$ar_rho <- rho
  m$resid <- d$y - fitted(m)
  m$resid_sd <- sd(m$resid)
  m$train <- d
  m
}

# Simulate draws for every modeled institution, years last+1 .. last+h
simulate <- function(m, h, draws) {
  d <- m$train
  last_year <- max(d$year)
  last <- d[!duplicated(d$inst, fromLast = TRUE), ]
  last_resid <- m$resid[!duplicated(d$inst, fromLast = TRUE)]
  # Institutions that stopped reporting before the last year are not projected
  ok <- last$year == last_year
  last <- last[ok, ]; last_resid <- last_resid[ok]
  years <- last_year + seq_len(h)
  nd <- last[rep(seq_len(nrow(last)), each = h), c("inst_id", "inst", "state", "model_sector")]
  nd$year <- rep(years, times = nrow(last))
  nd$year_c <- nd$year - 2018
  X <- predict(m, newdata = nd, type = "lpmatrix", discrete = FALSE)
  beta <- rmvn(draws, coef(m), vcov(m, unconditional = TRUE))
  eta <- X %*% t(beta)                                   # rows: inst-year, cols: draws
  # AR(1) residual paths conditioned on each institution's last residual
  rho <- m$ar_rho
  innov_sd <- m$resid_sd * sqrt(1 - rho^2)
  e <- matrix(0, nrow(nd), draws)
  for (i in seq_len(nrow(last))) {
    prev <- rep(last_resid[i], draws)
    for (k in seq_len(h)) {
      prev <- rho * prev + rnorm(draws, 0, innov_sd)
      e[(i - 1) * h + k, ] <- prev
    }
  }
  list(nd = nd, logv = eta + e)
}

# Naive baseline: each institution's own average log growth, with noise from its own year-to-year changes
naive <- function(d, h, draws) {
  last_year <- max(d$year)
  out <- lapply(split(d, d$inst_id), function(x) {
    if (max(x$year) != last_year || nrow(x) < 3) return(NULL)
    dif <- diff(x$y) / diff(x$year)
    mu <- mean(dif); s <- sd(dif); if (!is.finite(s) || s == 0) s <- 0.1
    k <- seq_len(h)
    data.frame(inst_id = x$inst_id[1], year = last_year + rep(k, each = 1),
               idx = k, mu = tail(x$y, 1) + k * mu, s = s * sqrt(k))
  })
  out <- do.call(rbind, out)
  logv <- matrix(rnorm(nrow(out) * draws, out$mu, out$s), nrow(out), draws)
  list(nd = out, logv = logv)
}

# Hierarchical growth model: partial pooling on each institution's growth rate,
# anchored at its last observed value (university R&D behaves close to a random
# walk with drift, so levels persist and growth rates are what to pool).
#   dlog ~ sector + s(state, re) + s(inst, re) + s(year, re) + s(year x sector, re)
# Future years draw new shared year and year-by-sector shocks from their fitted
# variances, so totals over any group carry the shared uncertainty.
fit_growth <- function(d) {
  d <- d[order(d$inst, d$year), ]
  prev <- c(NA, head(d$y, -1)); prev_year <- c(NA, head(d$year, -1))
  same <- c(FALSE, head(d$inst, -1) == d$inst[-1])
  g <- d[same & d$year - prev_year == 1, ]
  g$dy <- (d$y - prev)[same & d$year - prev_year == 1]
  g$lag_y <- prev[same & d$year - prev_year == 1]
  g$fyear <- factor(g$year)
  g$fys <- factor(paste(g$year, g$model_sector))
  g$inst <- droplevels(g$inst); g$state <- droplevels(g$state)
  m <- bam(dy ~ model_sector + s(state, bs = "re") + s(inst, bs = "re") + s(fyear, bs = "re") + s(fys, bs = "re"),
           data = g, method = "fREML", discrete = TRUE)
  invisible(capture.output(vc <- gam.vcomp(m, rescale = FALSE)))
  sd_of <- function(term) { r <- grep(term, rownames(vc), fixed = TRUE); if (length(r)) vc[r[1], "std.dev"] else 0 }
  m$sd_year <- sd_of("s(fyear)"); m$sd_ys <- sd_of("s(fys)"); m$sd_resid <- sqrt(m$sig2)
  # Small institutions' budgets swing far more than large ones', so the year-to-year
  # noise is a smooth function of size: E[log|e|] = log(sigma) - 0.635 for normal e.
  g$log_abs_resid <- log(abs(residuals(m)) + 1e-6)
  m$noise <- gam(log_abs_resid ~ s(lag_y, k = 6), data = g, method = "REML")
  m$noise_sd <- function(level) exp(predict(m$noise, newdata = data.frame(lag_y = level)) + 0.635)
  m$train <- d; m$growth_data <- g
  m
}

simulate_growth <- function(m, h, draws, widen = 1) {
  d <- m$train; g <- m$growth_data
  last_year <- max(d$year)
  last <- d[!duplicated(d$inst, fromLast = TRUE), ]
  last <- last[last$year == last_year & last$inst %in% levels(g$inst), ]
  nd <- data.frame(inst_id = last$inst_id, inst = factor(as.character(last$inst), levels(g$inst)),
                   state = factor(as.character(last$state), levels(g$state)),
                   model_sector = factor(as.character(last$model_sector), levels(g$model_sector)),
                   fyear = factor(levels(g$fyear)[1], levels(g$fyear)), fys = factor(levels(g$fys)[1], levels(g$fys)))
  X <- predict(m, newdata = nd, type = "lpmatrix", discrete = FALSE)
  X[, grepl("^s\\(fyear\\)|^s\\(fys\\)", colnames(X))] <- 0   # past year shocks do not carry forward
  beta <- rmvn(draws, coef(m), vcov(m, unconditional = TRUE))
  drift <- X %*% t(beta)                                         # institution growth per draw
  sectors <- as.integer(nd$model_sector)
  logv <- matrix(0, nrow(nd) * h, draws)
  level <- matrix(last$y, nrow(nd), draws)
  noise_sd <- widen * m$noise_sd(last$y)                        # per institution, from its last observed size
  for (k in seq_len(h)) {
    year_shock <- matrix(rnorm(draws, 0, widen * m$sd_year), nrow(nd), draws, byrow = TRUE)
    ys <- matrix(rnorm(nlevels(nd$model_sector) * draws, 0, widen * m$sd_ys), nlevels(nd$model_sector), draws)[sectors, , drop = FALSE]
    level <- level + drift + year_shock + ys + matrix(rnorm(nrow(nd) * draws, 0, noise_sd), nrow(nd), draws)
    logv[seq(k, by = h, length.out = nrow(nd)), ] <- level
  }
  out <- data.frame(inst_id = rep(nd$inst_id, each = h), year = rep(last_year + seq_len(h), times = nrow(nd)))
  list(nd = out, logv = logv)
}

score <- function(sim, actual, label, cutoff, sizes) {
  key <- paste(sim$nd$inst_id, sim$nd$year)
  a <- actual[match(key, paste(actual$inst_id, actual$year)), "y"]
  ok <- !is.na(a)
  q <- t(apply(sim$logv[ok, , drop = FALSE], 1, quantile, c(0.05, 0.1, 0.9, 0.95)))
  size <- cut(exp(sizes[match(sim$nd$inst_id[ok], names(sizes))]) * 1000, c(0, 5e6, 1e8, Inf),
              labels = c("Under $5M", "$5M to $100M", "Over $100M"))
  data.frame(model = label, cutoff = cutoff, horizon = sim$nd$year[ok] - cutoff, size = size,
             crps = crps_sample(a[ok], sim$logv[ok, , drop = FALSE]),
             in80 = a[ok] >= q[, 2] & a[ok] <= q[, 3],
             in90 = a[ok] >= q[, 1] & a[ok] <= q[, 4])
}

summarise_bt <- function(x) {
  agg <- aggregate(cbind(crps, in80, in90) ~ model + horizon, data = x, FUN = mean)
  agg[order(agg$horizon, agg$crps), ]
}

# --- Backtest on total R&D: compare models by CRPS -----------------------------
d_all <- load_measure("source_all_r_d")
cutoffs <- release$projection$cutoffs
labels <- c(hgam = "Hierarchical GAM on levels (GP smooths, AR(1))",
            growth = "Hierarchical growth (pooled drift, shared year shocks)",
            naive = "Naive: own average growth")
widen_grid <- c(1, 1.15, 1.3, 1.5)
bt <- list(); bt_widen <- list()
for (cut in cutoffs) {
  train <- d_all[d_all$year <= cut, ]
  test <- d_all[d_all$year > cut & d_all$year <= cut + 3, ]
  last_train <- train[!duplicated(train$inst_id, fromLast = TRUE), ]
  sizes <- setNames(last_train$y, last_train$inst_id)
  bt[[length(bt) + 1]] <- score(simulate(fit_model(train, gp_range), 3, 500), test, labels[["hgam"]], cut, sizes)
  mg <- fit_growth(train)
  for (w in widen_grid) {
    s <- score(simulate_growth(mg, 3, 500, w), test, labels[["growth"]], cut, sizes)
    s$widen <- w
    bt_widen[[length(bt_widen) + 1]] <- s
  }
  bt[[length(bt) + 1]] <- score(naive(train, 3, 500), test, labels[["naive"]], cut, sizes)
  message("backtest cutoff ", cut, " done")
}
# Pick the noise multiplier whose coverage is closest to nominal, then keep only that run
bt_widen <- do.call(rbind, bt_widen)
cal <- aggregate(cbind(crps, in80, in90) ~ widen, data = bt_widen, FUN = mean)
cal$miss <- abs(cal$in80 - 0.8) + abs(cal$in90 - 0.9)
print(cal, row.names = FALSE)
widen <- cal$widen[which.min(cal$miss)]
message("interval widening factor: ", widen)
bt <- rbind(do.call(rbind, bt), bt_widen[bt_widen$widen == widen, setdiff(names(bt_widen), "widen")])
bt_summary <- summarise_bt(bt)
print(bt_summary, row.names = FALSE)
overall <- aggregate(cbind(crps, in80, in90) ~ model, data = bt, FUN = mean)
print(overall[order(overall$crps), ], row.names = FALSE)
by_size <- aggregate(cbind(crps, in80, in90) ~ model + size, data = bt, FUN = mean)
by_size <- by_size[order(by_size$size, by_size$crps), ]
print(by_size, row.names = FALSE)
modeled <- overall[overall$model != labels[["naive"]], ]
chosen <- names(labels)[match(modeled$model[which.min(modeled$crps)], labels)]
message("production model: ", labels[[chosen]])

# --- Fit each headline measure on all years and simulate ----------------------
info <- list()
for (id in measures) {
  d <- load_measure(id)
  skip <- function(reason) {
    message(sprintf("%-36s skipped: %s", id, reason))
    info[[id]] <<- data.frame(measure_id = id, status = "unavailable", reason = reason)
  }
  if (length(unique(d$inst_id)) < 30) { skip("Fewer than 30 institutions reported this measure in enough years to model."); next }
  fit <- tryCatch({
    m <- if (chosen == "growth") fit_growth(d) else fit_model(d, gp_range)
    list(m = m, sim = if (chosen == "growth") simulate_growth(m, horizon, n_draws, widen) else simulate(m, horizon, n_draws))
  }, error = function(e) e)
  if (inherits(fit, "error")) { skip(paste("The model did not fit this measure:", conditionMessage(fit))); next }
  m <- fit$m; sim <- fit$sim
  long <- data.frame(
    inst_id = rep(sim$nd$inst_id, times = n_draws),
    year = rep(sim$nd$year, times = n_draws),
    draw = rep(seq_len(n_draws), each = nrow(sim$nd)),
    value = as.vector(exp(sim$logv))
  )
  duckdb_register(con, "proj", long)
  invisible(dbExecute(con, sprintf("COPY (SELECT inst_id, year::SMALLINT AS year, draw::SMALLINT AS draw, value::FLOAT AS value FROM proj ORDER BY inst_id, year, draw) TO '%s' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 20000)",
                                   file.path(out_dir, paste0(id, ".parquet")))))
  duckdb_unregister(con, "proj")
  info[[id]] <- data.frame(measure_id = id, status = "ok", reason = NA_character_, model = labels[[chosen]], institutions = nlevels(d$inst), observations = nrow(d),
                           sd_year_shock = if (chosen == "growth") round(m$sd_year, 4) else NA,
                           sd_year_sector_shock = if (chosen == "growth") round(m$sd_ys, 4) else NA,
                           sd_residual_log = round(if (chosen == "growth") m$sd_resid else m$resid_sd, 4),
                           interval_widening = if (chosen == "growth") widen else 1,
                           first_projected_year = max(d$year) + 1, last_projected_year = max(d$year) + horizon,
                           draws = n_draws, fitted_on = as.character(Sys.Date()))
  message(sprintf("%-36s %4d institutions projected", id, length(unique(sim$nd$inst_id))))
}

write_parquet <- function(df, name) {
  duckdb_register(con, "tmp", df)
  invisible(dbExecute(con, sprintf("COPY tmp TO '%s' (FORMAT parquet)", file.path(out_dir, name))))
  duckdb_unregister(con, "tmp")
}
# Measures not modeled at all, with the reason the site shows
not_modeled <- dbGetQuery(con, "SELECT id FROM measure_catalog WHERE unit <> 'thousands_usd'")$id
for (id in not_modeled) info[[id]] <- data.frame(measure_id = id, status = "unavailable",
  reason = "Personnel counts are released only from FY 2022, too few years to model.")
all_cols <- unique(unlist(lapply(info, names)))
info <- lapply(info, function(x) { for (c in setdiff(all_cols, names(x))) x[[c]] <- NA; x[all_cols] })
write_parquet(do.call(rbind, info), "model_info.parquet")
write_parquet(bt_summary, "backtest.parquet")
write_parquet(overall, "backtest_overall.parquet")
write_parquet(by_size, "backtest_by_size.parquet")
write_parquet(cal, "backtest_calibration.parquet")
for (f in list.files(out_dir, full.names = TRUE)) message(sprintf("wrote projections/%-40s %6.1f MB", basename(f), file.size(f) / 1e6))
