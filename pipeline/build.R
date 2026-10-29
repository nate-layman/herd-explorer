# Build the HERD Explorer database from the NCSES public microdata.
#
# Downloads the standard-form and short-form files for each fiscal year, combines
# them into one long table, adds NCSES's published national totals and COGR's
# count of federal research requirements, checks the rollups against the
# published tables, and writes one DuckDB database for the site:
#   docs/data/herd.duckdb
#
# It also writes docs/data/meta.json, the years and labels the site's text reads.
# Years and the NCSES publication come from pipeline/release.yml.
#
# Usage: Rscript pipeline/build.R

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(readxl)
})

root <- getwd()
if (!file.exists(file.path(root, "pipeline", "build.R"))) stop("run from the repository root: Rscript pipeline/build.R")
source(file.path(root, "pipeline", "release.R"))
release <- read_release(root)
first_year <- release$first_year
last_year <- release$last_year
microdata_url <- "https://ncses.nsf.gov/821/assets/0/files/higher_education_r_and_d_%d%s.zip"
microdata_page <- "https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development"
# The latest release's data tables carry the published national totals
tables_url <- release$tables$zip
tables_page <- release$tables$page
tables_label <- release$tables$label
cogr_page <- "https://www.cogr.edu/changes-federal-research-requirements-1991"

raw_dir <- file.path(root, "pipeline", "raw")
out_dir <- file.path(root, "docs", "data")
db_path <- file.path(out_dir, "herd.duckdb")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(root, "pipeline", "validate.R"))
source(file.path(root, "pipeline", "metrics.R"))
source(file.path(root, "pipeline", "downloads.R"))

fetch <- function(url, dest) {
  if (!file.exists(dest)) {
    message("downloading ", url)
    download.file(url, dest, mode = "wb", quiet = TRUE,
                  headers = c(`User-Agent` = "Mozilla/5.0 (herd-explorer build)"))
  }
  dest
}

# Extract the single CSV in an NCSES zip and return its path
csv_from_zip <- function(zip_path) {
  csv <- grep("\\.csv$", unzip(zip_path, list = TRUE)$Name, value = TRUE, ignore.case = TRUE)
  if (length(csv) != 1) stop(basename(zip_path), ": expected one CSV, found ", paste(csv, collapse = ", "))
  exdir <- sub("\\.zip$", "", zip_path)
  unzip(zip_path, files = csv, exdir = exdir, overwrite = TRUE)
  file.path(exdir, csv)
}

files <- do.call(rbind, lapply(first_year:last_year, function(y) {
  data.frame(year = y, form = c("standard", "short"), suffix = c("", "_short"))
}))
files$url <- sprintf(microdata_url, files$year, files$suffix)
files$csv <- vapply(seq_len(nrow(files)), function(i) {
  csv_from_zip(fetch(files$url[i], file.path(raw_dir, basename(files$url[i]))))
}, "")
tables_dir <- file.path(raw_dir, paste0(release$tables$publication, "-tables"))
unzip(fetch(tables_url, file.path(raw_dir, paste0(release$tables$publication, "-tables.zip"))), exdir = tables_dir, overwrite = TRUE)

if (file.exists(db_path)) invisible(file.remove(db_path))
con <- dbConnect(duckdb(), db_path)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# --- HERD microdata ------------------------------------------------------------
# Every column is read as text; NCSES files vary slightly by year and form.
# Most files are UTF-8; any that are not are Windows-1252 and get a UTF-8 copy.
# NCSES reports dollar amounts in thousands. They are multiplied by 1,000 here, once,
# so every table, download and projection is in whole dollars.
files$csv <- vapply(files$csv, function(f) {
  lines <- readLines(f, warn = FALSE)
  if (all(validUTF8(lines))) return(f)
  utf8 <- sub("\\.csv$", "_utf8.csv", f)
  writeLines(iconv(lines, from = "CP1252", to = "UTF-8"), utf8, useBytes = TRUE)
  utf8
}, "", USE.NAMES = FALSE)
selects <- sprintf(
  "SELECT '%s' AS form, * FROM read_csv('%s', all_varchar = true, header = true)",
  files$form, files$csv
)
invisible(dbExecute(con, paste("CREATE TEMP TABLE raw AS", paste(selects, collapse = " UNION ALL BY NAME "))))

invisible(dbExecute(con, "
  CREATE TABLE facts AS
  SELECT
    CAST(year AS INTEGER)        AS year,
    inst_id,
    form,
    questionnaire_no             AS question_no,
    question,
    \"row\"                      AS row_label,
    NULLIF(\"column\", '')       AS column_label,
    TRY_CAST(data AS DOUBLE) * CASE WHEN unit = 'thousands_usd' THEN 1000 ELSE 1 END AS value,
    NULLIF(status, '')           AS status,
    CASE WHEN unit = 'thousands_usd' THEN 'dollars' ELSE unit END AS unit
  FROM (
    SELECT *,
      CASE
        WHEN questionnaire_no = '01.1' THEN 'code'
        WHEN questionnaire_no = '13'   THEN 'dollars'
        WHEN questionnaire_no = '15'   THEN 'headcount'
        WHEN questionnaire_no = '16'   THEN 'fte'
        ELSE 'thousands_usd'
      END AS unit
    FROM raw)
  ORDER BY year, inst_id, question_no
"))

invisible(dbExecute(con, "
  CREATE TABLE institutions AS
  SELECT DISTINCT
    CAST(year AS INTEGER)        AS year,
    inst_id,
    ncses_inst_id,
    ipeds_unitid,
    inst_name_long               AS name,
    inst_city                    AS city,
    inst_state_code              AS state,
    CASE toc_code WHEN '1' THEN 'Public' WHEN '2' THEN 'Private' END AS control,
    CASE hdg_code WHEN '1' THEN 'Doctorate' WHEN '2' THEN 'Master''s' WHEN '3' THEN 'Bachelor''s'
                  WHEN '4' THEN 'Associate''s' WHEN '5' THEN 'No degree'
                  WHEN '6' THEN 'Professional degree' END AS highest_degree,
    hbcu_flag = '1'              AS hbcu,
    med_sch_flag = 'T'           AS medical_school,
    hhe_flag = '1'               AS high_hispanic_enrollment,
    form
  FROM raw
  ORDER BY year, inst_id
"))

dupes <- dbGetQuery(con, "SELECT count(*) AS n FROM (SELECT year, inst_id FROM institutions GROUP BY ALL HAVING count(*) > 1)")$n
if (dupes > 0) stop(dupes, " institution-years have conflicting attributes; inspect before publishing")

# --- NCSES published national totals -------------------------------------------
# Tables 2 and 12 carry the split of institution funds and of indirect costs that
# NCSES does not release per institution (HERD data user guide, section 1.1.4).
table_path <- function(n) {
  f <- list.files(tables_dir, sprintf("tab%03d\\.xlsx$", n), full.names = TRUE, recursive = TRUE)
  if (length(f) != 1) stop(sprintf("expected one Table %d workbook in %s, found %d; check tables in release.yml", n, basename(tables_url), length(f)))
  f
}
funds_table <- as.integer(release$tables$source_of_funds)
cost_table <- as.integer(release$tables$type_of_cost)
funds_source <- sprintf("%s Table %d", tables_label, funds_table)
cost_source <- sprintf("%s Table %d", tables_label, cost_table)

read_table2 <- function() {
  x <- read_excel(table_path(funds_table), col_names = FALSE, .name_repair = "minimal")
  start <- which(x[[1]] == "All institutions")[1] + 1
  stop_at <- which(x[[1]] == "Short form institutionsa" | grepl("^Short form", x[[1]]))[1] - 1
  x <- x[start:stop_at, ]
  measures <- c("All R&D", "Federal government", "State and local government", "Institution funds",
                "Institution funds: institutionally financed research", "Institution funds: cost sharing",
                "Institution funds: unrecovered indirect costs", "Business", "Nonprofit organizations",
                "All other sources")
  do.call(rbind, lapply(seq_along(measures), function(j) data.frame(
    source_table = funds_source, population = "All institutions", year = as.integer(x[[1]]),
    dimension = "Source of funds", measure = measures[j], value = as.numeric(x[[j + 1]])
  )))
}

read_table12 <- function() {
  x <- read_excel(table_path(cost_table), col_names = FALSE, .name_repair = "minimal")
  years <- as.integer(unlist(x[4, -1]))
  start <- which(x[[1]] == "All institutions")[1] + 1
  stop_at <- which(x[[1]] == "Doctorate")[1] - 1
  x <- x[start:stop_at, ]
  do.call(rbind, lapply(seq_len(nrow(x)), function(i) data.frame(
    source_table = cost_source, population = "Standard-form institutions", year = years,
    dimension = "Type of cost", measure = x[[1]][i], value = as.numeric(unlist(x[i, -1]))
  )))
}

published <- rbind(read_table2(), read_table12())
published <- published[!is.na(published$year) & !is.na(published$value), ]
# Table 12 repeats "Recovered" and "Unrecovered" under indirect costs; name them fully
published$measure[published$measure == "Recovered"] <- "Indirect costs: recovered"
published$measure[published$measure == "Unrecovered"] <- "Indirect costs: unrecovered"
# Published in thousands of dollars, like the microdata; whole dollars here
published$value <- published$value * 1000
published$unit <- "dollars"
dbWriteTable(con, "national_published", published)

# --- COGR federal research requirements ----------------------------------------
# COGR publishes the cumulative count only as data labels on its Figure 1, not as a table,
# so the labels are typed into pipeline/cogr_requirements.csv
cogr <- read.csv(file.path(root, "pipeline", "cogr_requirements.csv"))
cogr$year <- as.integer(cogr$year)
cogr$source_note <- sprintf("Data labels on COGR Figure 1, Changes in Federal Research Requirements Since 1991 (updated %s)", release$cogr$updated)
if (max(cogr$year) < last_year)
  warning(sprintf("cogr_requirements.csv ends in %d, before %d; the Trends page's workload chart ends there too", max(cogr$year), last_year), call. = FALSE)
dbWriteTable(con, "cogr_requirements", cogr)

# --- Carnegie Classification 2021 ----------------------------------------------
# Joined on IPEDS unit ID. The 2021 edition is held fixed across all years so a
# group means the same institutions in every year. R1 and R2 status depends partly
# on R&D spending, so it is a grouping label here, not a predictor that moves.
carnegie_url <- "https://carnegieclassifications.acenet.edu/wp-content/uploads/2023/03/CCIHE2021-PublicData.xlsx"
carnegie_page <- "https://carnegieclassifications.acenet.edu/resource/2021-update-public-file/"
cc <- read_excel(fetch(carnegie_url, file.path(raw_dir, basename(carnegie_url))), sheet = "Data")
basic <- cc$basic2021
sector <- ifelse(basic == 15, "R1",
          ifelse(basic == 16, "R2",
          ifelse(basic == 17, "Doctoral/Professional",
          ifelse(basic %in% 18:20, "Master's",
          ifelse(basic %in% 21:22, "Baccalaureate",
          ifelse(basic == 25, "Special focus: medical",
          ifelse(basic == 27, "Special focus: research institution",
          ifelse(basic %in% c(24, 26, 28:32), "Special focus: other",
          ifelse(basic %in% c(1:14, 23, 33), "Associate's and tribal", "Not classified")))))))))
carnegie <- data.frame(
  ipeds_unitid = as.character(cc$unitid),
  basic2021 = as.integer(basic),
  sector = sector,
  msi = cc$msi == 1,
  hsi = cc$hsi == 1,
  tribal = cc$tribal == 1,
  land_grant = cc$landgrnt == 1
)
dbWriteTable(con, "carnegie_2021", carnegie)

# Some HERD reporting units have no IPEDS ID (combined campuses, system offices,
# independent research institutes) or an ID Carnegie no longer uses. A hand-checked
# crosswalk maps the ones with meaningful R&D; see pipeline/carnegie_overrides.csv.
overrides <- read.csv(file.path(root, "pipeline", "carnegie_overrides.csv"), colClasses = "character")
overrides[overrides == ""] <- NA
dbWriteTable(con, "carnegie_overrides", overrides, temporary = TRUE)

# One sector per institution, from any year it reported an IPEDS ID
invisible(dbExecute(con, "
  CREATE TABLE institution_groups AS
  WITH ids AS (
    SELECT inst_id, max(ipeds_unitid) AS ipeds_unitid
    FROM institutions GROUP BY inst_id
  )
  SELECT ids.inst_id,
         coalesce(o.carnegie_unitid, ids.ipeds_unitid)                 AS carnegie_unitid,
         coalesce(o.sector_override, c.sector, 'Not classified')        AS sector,
         CASE WHEN o.sector_override IS NOT NULL THEN 'Assigned by HERD Explorer'
              WHEN o.carnegie_unitid IS NOT NULL AND c.sector IS NOT NULL THEN 'Carnegie 2021 via crosswalk'
              WHEN c.sector IS NOT NULL THEN 'Carnegie 2021'
              ELSE 'Not classified' END                                AS sector_source,
         o.note                                                         AS crosswalk_note,
         coalesce(c.msi, false)                                         AS msi,
         coalesce(c.hsi, false)                                         AS hsi,
         coalesce(c.tribal, false)                                      AS tribal,
         coalesce(c.land_grant, false)                                  AS land_grant
  FROM ids
  LEFT JOIN carnegie_overrides o ON o.inst_id = ids.inst_id
  LEFT JOIN carnegie_2021 c ON c.ipeds_unitid = coalesce(o.carnegie_unitid, ids.ipeds_unitid)
"))
bad <- dbGetQuery(con, "SELECT o.inst_id, o.herd_name FROM carnegie_overrides o
                        LEFT JOIN carnegie_2021 c ON c.ipeds_unitid = o.carnegie_unitid
                        WHERE o.carnegie_unitid IS NOT NULL AND c.ipeds_unitid IS NULL")
if (nrow(bad)) stop("crosswalk IDs not found in Carnegie 2021: ", paste(bad$herd_name, collapse = "; "))
unclassified <- dbGetQuery(con, "
  SELECT count(DISTINCT g.inst_id) AS n, coalesce(sum(f.value), 0) / 1e6 AS rd_m
  FROM institution_groups g LEFT JOIN facts f ON f.inst_id = g.inst_id AND f.question_no = '01.g' AND f.year = %d
  WHERE g.sector = 'Not classified'" |> sprintf(last_year))
message(sprintf("Not classified: %d institutions, $%.0fM of FY %d R&D", unclassified$n, unclassified$rd_m, last_year))

# --- Institution locations -----------------------------------------------------
# Latitude and longitude from the IPEDS directory file (HD) of the year closest to the
# last year each institution reported to HERD, so closed or merged institutions keep
# the location they had. Units HERD reports without an IPEDS ID, and units IPEDS does
# not list (research institutes, military colleges), come from a hand-checked
# crosswalk; see pipeline/location_overrides.csv.
hd_url <- "https://nces.ed.gov/ipeds/datacenter/data/HD%d.zip"
hd_page <- "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx?year=-1&sid=HD"
read_hd <- function(y) {
  zip <- file.path(raw_dir, sprintf("HD%d.zip", y))
  got <- tryCatch(fetch(sprintf(hd_url, y), zip), error = function(e) { unlink(zip); NULL })
  if (is.null(got)) { message("IPEDS HD", y, " is not available yet; using the other years"); return(NULL) }
  lines <- readLines(csv_from_zip(zip), warn = FALSE)
  if (!all(validUTF8(lines))) lines <- iconv(lines, from = "CP1252", to = "UTF-8")
  x <- read.csv(text = lines, colClasses = "character", check.names = FALSE)
  names(x) <- toupper(trimws(sub("^﻿", "", names(x))))
  data.frame(year = y, unitid = x$UNITID,
             latitude = suppressWarnings(as.numeric(x$LATITUDE)), longitude = suppressWarnings(as.numeric(x$LONGITUD)))
}
hd <- do.call(rbind, lapply(first_year:last_year, read_hd))
hd <- hd[!is.na(hd$latitude) & !is.na(hd$longitude) & abs(hd$latitude) <= 90 & abs(hd$longitude) <= 180, ]
dbWriteTable(con, "ipeds_locations", hd, temporary = TRUE)
loc_overrides <- read.csv(file.path(root, "pipeline", "location_overrides.csv"), colClasses = "character")
loc_overrides[loc_overrides == ""] <- NA
loc_overrides$latitude <- as.numeric(loc_overrides$latitude)
loc_overrides$longitude <- as.numeric(loc_overrides$longitude)
dbWriteTable(con, "location_overrides", loc_overrides, temporary = TRUE)
bad <- dbGetQuery(con, "SELECT herd_name FROM location_overrides o
                        WHERE (o.latitude IS NULL) = (o.ipeds_unitid IS NULL)
                           OR (o.ipeds_unitid IS NOT NULL AND o.ipeds_unitid NOT IN (SELECT unitid FROM ipeds_locations))")
if (nrow(bad)) stop("location_overrides.csv rows need either an IPEDS ID found in HD or a latitude and longitude: ", paste(bad$herd_name, collapse = "; "))

# HERD's own IPEDS ID first: the Carnegie crosswalk maps some campuses to a system office
invisible(dbExecute(con, "
  CREATE TABLE institution_locations AS
  WITH ids AS (
    SELECT inst_id, max(ipeds_unitid) AS ipeds_unitid, max(year) AS last_year
    FROM institutions GROUP BY inst_id
  ),
  keyed AS (
    SELECT ids.inst_id, ids.last_year, o.latitude AS o_lat, o.longitude AS o_lon,
           coalesce(o.ipeds_unitid, ids.ipeds_unitid, g.carnegie_unitid) AS unitid
    FROM ids JOIN institution_groups g USING (inst_id)
    LEFT JOIN location_overrides o USING (inst_id)
  ),
  from_ipeds AS (
    SELECT k.inst_id, h.latitude, h.longitude, h.year
    FROM keyed k JOIN ipeds_locations h ON h.unitid = k.unitid
    QUALIFY row_number() OVER (PARTITION BY k.inst_id ORDER BY abs(h.year - k.last_year), h.year DESC) = 1
  )
  SELECT k.inst_id,
         coalesce(k.o_lat, i.latitude)  AS latitude,
         coalesce(k.o_lon, i.longitude) AS longitude,
         CASE WHEN k.o_lat IS NOT NULL THEN 'Entered by HERD Explorer'
              WHEN i.year IS NOT NULL THEN 'IPEDS HD' || i.year END AS location_source
  FROM keyed k LEFT JOIN from_ipeds i USING (inst_id)
  ORDER BY inst_id
"))
unlocated <- dbGetQuery(con, sprintf("
  SELECT i.name FROM institution_locations l JOIN institutions i ON i.inst_id = l.inst_id AND i.year = %d
  WHERE l.latitude IS NULL", last_year))
if (nrow(unlocated))
  warning(sprintf("%d institutions reporting in FY %d have no location; add them to pipeline/location_overrides.csv: %s",
                  nrow(unlocated), last_year, paste(unlocated$name, collapse = "; ")), call. = FALSE)
message(sprintf("Located: %d of %d institutions",
                dbGetQuery(con, "SELECT count(latitude) AS n FROM institution_locations")$n,
                dbGetQuery(con, "SELECT count(*) AS n FROM institution_locations")$n))

# --- Provenance ----------------------------------------------------------------
sources <- rbind(
  data.frame(table_name = "facts, institutions", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("HERD Survey public microdata, FY %d-%d, standard and short form", first_year, last_year),
             url = microdata_page, files = paste(basename(files$url), collapse = "; ")),
  data.frame(table_name = "national_published", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("HERD Survey FY %d data tables (%s), Tables %d and %d", last_year, tables_label, funds_table, cost_table),
             url = tables_page, files = basename(tables_url)),
  data.frame(table_name = "cogr_requirements", publisher = "Council on Governmental Relations (COGR)",
             title = sprintf("Changes in Federal Research Requirements Since 1991, Figure 1 (updated %s)", release$cogr$updated),
             url = cogr_page, files = "Figure 1 data labels, entered by hand"),
  data.frame(table_name = "carnegie_2021, institution_groups", publisher = "American Council on Education, Carnegie Classification",
             title = "Carnegie Classification of Institutions of Higher Education, 2021 update public data file",
             url = carnegie_page, files = basename(carnegie_url)),
  data.frame(table_name = "institution_locations", publisher = "NCES, U.S. Department of Education",
             title = sprintf("IPEDS Institutional Characteristics, directory information (HD), %d-%d: latitude and longitude", min(hd$year), max(hd$year)),
             url = hd_page, files = paste(sprintf("HD%d.zip", sort(unique(hd$year))), collapse = "; "))
)
sources$built_on <- as.character(Sys.Date())
dbWriteTable(con, "sources", sources)

# Every year in release.yml must be in the microdata, and no others
got <- dbGetQuery(con, "SELECT DISTINCT year FROM facts ORDER BY year")$year
if (!identical(as.integer(got), first_year:last_year))
  stop("microdata years ", paste(range(got), collapse = "-"), " do not match release.yml ", first_year, "-", last_year)

validate(con, funds_source, cost_source)
build_metrics(con)
build_downloads(con, out_dir, first_year, last_year)
jsonlite::write_json(c(site_meta(release), built_on = as.character(Sys.Date())),
                     file.path(out_dir, "meta.json"), auto_unbox = TRUE, pretty = TRUE)
message("wrote meta.json")

# Parquet copies for downloads and for anyone who prefers files to a database
for (t in c("facts", "metrics", "measure_catalog", "institutions", "institution_groups", "institution_locations", "national_published", "cogr_requirements", "sources")) {
  invisible(dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT parquet, COMPRESSION zstd)", t, file.path(out_dir, paste0(t, ".parquet")))))
}
invisible(dbExecute(con, "CHECKPOINT"))
for (f in list.files(out_dir, pattern = "\\.(parquet|duckdb)$", full.names = TRUE)) message(sprintf("wrote %-45s %6.1f MB", basename(f), file.size(f) / 1e6))
