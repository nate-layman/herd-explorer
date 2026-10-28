# Read pipeline/release.yml and derive everything that follows from it.
# Shared by pipeline/build.R and model/fit.R so the years are set in one place.

read_release <- function(root = getwd()) {
  r <- yaml::read_yaml(file.path(root, "pipeline", "release.yml"))
  r$first_year <- as.integer(r$first_year)
  r$last_year <- as.integer(r$last_year)
  if (r$last_year < r$first_year) stop("release.yml: last_year is before first_year")
  pub <- r$tables$publication
  if (!grepl("^nsf\\d{5}$", pub)) stop("release.yml: tables.publication should look like nsf26304, got ", pub)
  r$tables$page <- sprintf("https://ncses.nsf.gov/pubs/%s", pub)
  r$tables$zip <- sprintf("https://ncses.nsf.gov/pubs/%1$s/assets/data-tables/%1$s-data-tables-tables-excels.zip", pub)
  # nsf26304 -> NSF 26-304, the way NCSES cites it
  r$tables$label <- sprintf("NSF %s-%s", substr(pub, 4, 5), substr(pub, 6, 8))
  h <- as.integer(r$projection$horizon)
  n <- as.integer(r$projection$backtest_cutoffs)
  r$projection$horizon <- h
  r$projection$first_year <- r$last_year + 1L
  r$projection$last_year <- r$last_year + h
  # Each cutoff is scored on the 3 years after it, so the last cutoff is last_year - 3
  r$projection$cutoffs <- seq(r$last_year - 3L - n + 1L, r$last_year - 3L)
  r
}

# The years and labels the site reads (docs/data/meta.json)
site_meta <- function(r) list(
  first_year = r$first_year,
  last_year = r$last_year,
  year_count = r$last_year - r$first_year + 1L,
  projection_first_year = r$projection$first_year,
  projection_last_year = r$projection$last_year,
  projection_horizon = r$projection$horizon,
  backtest_first_cutoff = min(r$projection$cutoffs),
  backtest_last_cutoff = max(r$projection$cutoffs),
  tables_publication = r$tables$label,
  tables_page = r$tables$page,
  cogr_updated = r$cogr$updated
)
