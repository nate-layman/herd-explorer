# Reshape the projection draws into the small files the site loads, run after model/fit.R.
#
#   by_group/<measure>.parquet       draws already summed for every group Trends can show:
#                                    split, grp, year, draw, value
#   by_institution/inst_id=<id>/     every measure's draws for one institution, for Compare:
#                                    measure_id, year, draw, value
#
# Group totals include institutions the model did not project (too few years, or not
# reporting in the last year) at their last reported value, held flat, the same rule the
# site used when it summed institutions itself. Draws keep their index, so groups can be
# combined later (for example into "All other") by adding them draw by draw.
#
# Usage: Rscript model/aggregate.R

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

root <- getwd()
if (!file.exists(file.path(root, "model", "aggregate.R"))) stop("run from the repository root: Rscript model/aggregate.R")
out <- file.path(root, "model", "output")
con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
db <- file.path(root, "docs", "data", "herd.duckdb")
invisible(dbExecute(con, sprintf("ATTACH '%s' AS herd (READ_ONLY)", db)))

# One row per institution and split, with the labels the Trends page uses
invisible(dbExecute(con, "
  CREATE TEMP TABLE memberships AS
  WITH latest AS (
    SELECT * FROM herd.institutions QUALIFY row_number() OVER (PARTITION BY inst_id ORDER BY year DESC) = 1),
  i AS (SELECT l.inst_id, l.state, l.control, l.medical_school, l.hbcu, g.sector, g.msi, g.land_grant
        FROM latest l JOIN herd.institution_groups g USING (inst_id))
  SELECT inst_id, '' AS split, 'National total' AS grp FROM i
  UNION ALL SELECT inst_id, 'sector', coalesce(sector, 'Unknown') FROM i
  UNION ALL SELECT inst_id, 'control', coalesce(control, 'Unknown') FROM i
  UNION ALL SELECT inst_id, 'state', coalesce(state, 'Unknown') FROM i
  UNION ALL SELECT inst_id, 'msi', CASE WHEN msi THEN 'Minority-serving' ELSE 'Not minority-serving' END FROM i
  UNION ALL SELECT inst_id, 'hbcu', CASE WHEN hbcu THEN 'HBCU' ELSE 'Not an HBCU' END FROM i
  UNION ALL SELECT inst_id, 'medical_school', CASE WHEN medical_school THEN 'Medical school' ELSE 'No medical school' END FROM i
  UNION ALL SELECT inst_id, 'land_grant', CASE WHEN land_grant THEN 'Land-grant' ELSE 'Not land-grant' END FROM i"))

measures <- dbGetQuery(con, sprintf("SELECT measure_id FROM read_parquet('%s') WHERE status = 'ok'",
                                    file.path(out, "model_info.parquet")))$measure_id
# Fingerprint of the detail draws. Every derived file and model_info carry it, and the
# site refuses to draw a band unless they agree, so aggregates can never drift from details.
detail_files <- file.path(out, paste0(sort(measures), ".parquet"))
manifest <- tempfile()
writeLines(paste(basename(detail_files), tools::md5sum(detail_files)), manifest)
fit_id <- substr(unname(tools::md5sum(manifest)), 1, 12)
message("fit_id: ", fit_id)

dir.create(file.path(out, "by_group"), showWarnings = FALSE)
for (id in measures) {
  f <- file.path(out, paste0(id, ".parquet"))
  invisible(dbExecute(con, sprintf("
    COPY (
      WITH draws AS (SELECT * FROM read_parquet('%1$s')),
      flat AS (  -- last reported value of institutions without draws
        SELECT m.inst_id, m.value FROM herd.metrics m
        WHERE m.measure_id = '%2$s'
          AND m.year = (SELECT max(year) FROM herd.metrics WHERE measure_id = '%2$s')
          AND m.inst_id NOT IN (SELECT DISTINCT inst_id FROM draws)),
      modeled AS (
        SELECT b.split, b.grp, d.year, d.draw, sum(d.value) AS value
        FROM draws d JOIN memberships b USING (inst_id) GROUP BY ALL),
      held AS (
        SELECT b.split, b.grp, sum(f.value) AS value
        FROM flat f JOIN memberships b USING (inst_id) GROUP BY ALL),
      -- Every group that has modeled or held institutions, for every year and draw, so a
      -- group made only of held institutions is not dropped
      grid AS (
        SELECT g.split, g.grp, yd.year, yd.draw
        FROM (SELECT split, grp FROM modeled UNION SELECT split, grp FROM held) g,
             (SELECT DISTINCT year, draw FROM draws) yd)
      SELECT grid.split, grid.grp, grid.year::SMALLINT AS year, grid.draw::SMALLINT AS draw,
             (coalesce(m.value, 0) + coalesce(h.value, 0))::FLOAT AS value, '%4$s' AS fit_id
      FROM grid
      LEFT JOIN modeled m USING (split, grp, year, draw)
      LEFT JOIN held h USING (split, grp)
      ORDER BY grid.split, grid.grp, grid.year, grid.draw
    ) TO '%3$s' (FORMAT parquet, COMPRESSION zstd)",
    f, id, file.path(out, "by_group", paste0(id, ".parquet")), fit_id)))
}

# Every measure's draws, one folder per institution
files <- paste0("'", file.path(out, paste0(measures, ".parquet")), "'", collapse = ", ")
unlink(file.path(out, "by_institution"), recursive = TRUE)
invisible(dbExecute(con, sprintf("
  COPY (
    SELECT inst_id, regexp_extract(filename, '([^/]+)\\.parquet$', 1) AS measure_id, year, draw, value, '%s' AS fit_id
    FROM read_parquet([%s], filename = true)
    ORDER BY inst_id, measure_id, year, draw
  ) TO '%s' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (inst_id))",
  fit_id, files, file.path(out, "by_institution"))))

# --- Consistency checks: stop before anything is published if aggregates disagree ----
problems <- character()
for (id in measures) {
  bad <- dbGetQuery(con, sprintf("
    WITH detail AS (SELECT year, draw, sum(value) AS v FROM read_parquet('%1$s') GROUP BY ALL),
    flat AS (SELECT coalesce(sum(value), 0) AS v FROM herd.metrics
             WHERE measure_id = '%2$s' AND year = (SELECT max(year) FROM herd.metrics WHERE measure_id = '%2$s')
               AND inst_id NOT IN (SELECT DISTINCT inst_id FROM read_parquet('%1$s'))),
    grp AS (SELECT * FROM read_parquet('%3$s')),
    national AS (SELECT year, draw, value AS v FROM grp WHERE split = ''),
    sectors AS (SELECT year, draw, sum(value) AS v FROM grp WHERE split = 'sector' GROUP BY ALL)
    SELECT
      (SELECT max(abs(n.v - d.v - f.v) / greatest(n.v, 1)) FROM national n JOIN detail d USING (year, draw), flat f) AS national_vs_detail,
      (SELECT max(abs(n.v - s.v) / greatest(n.v, 1)) FROM national n JOIN sectors s USING (year, draw)) AS sectors_vs_national,
      (SELECT count(DISTINCT fit_id) FROM grp) AS fit_ids",
    file.path(out, paste0(id, ".parquet")), id, file.path(out, "by_group", paste0(id, ".parquet"))))
  # Float32 storage allows about 1e-6 relative error
  if (is.na(bad$national_vs_detail) || bad$national_vs_detail > 1e-5 || bad$sectors_vs_national > 1e-5 || bad$fit_ids != 1)
    problems <- c(problems, sprintf("%s: national vs detail %.2g, sectors vs national %.2g, fit ids %d",
                                    id, bad$national_vs_detail, bad$sectors_vs_national, bad$fit_ids))
}
inst_check <- dbGetQuery(con, sprintf("
  SELECT count(*) AS n FROM (
    SELECT measure_id, year, draw, sum(value) AS v FROM read_parquet('%s/*/*.parquet') GROUP BY ALL) i
  JOIN (SELECT regexp_extract(filename, '([^/]+)\\.parquet$', 1) AS measure_id, year, draw, sum(value) AS v
        FROM read_parquet([%s], filename = true) GROUP BY ALL) d USING (measure_id, year, draw)
  WHERE abs(i.v - d.v) / greatest(d.v, 1) > 1e-5", file.path(out, "by_institution"), files))$n
if (inst_check > 0) problems <- c(problems, sprintf("by_institution disagrees with detail draws in %d measure-year-draws", inst_check))
if (length(problems)) { writeLines(problems); stop("aggregates do not match the detail draws; nothing published") }
message(sprintf("checks passed: %d measures, group and institution files match the detail draws", length(measures)))

# Stamp the fingerprint into model_info, which the site reads first
info_path <- file.path(out, "model_info.parquet")
info <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", info_path))
info$fit_id <- fit_id
duckdb_register(con, "info_new", info)
invisible(dbExecute(con, sprintf("COPY info_new TO '%s' (FORMAT parquet)", info_path)))
