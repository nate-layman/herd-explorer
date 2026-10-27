# Build the HERD Explorer database from the NCSES public microdata.
#
# Downloads the standard-form and short-form files for each fiscal year, combines
# them into one long table, adds NCSES's published national totals and COGR's
# count of federal research requirements, checks the rollups against the
# published tables, and writes one DuckDB database for the site:
#   docs/data/herd.duckdb
#
# Usage: Rscript pipeline/build.R

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(readxl)
})

first_year <- 2012L
last_year <- 2024L
microdata_url <- "https://ncses.nsf.gov/821/assets/0/files/higher_education_r_and_d_%d%s.zip"
microdata_page <- "https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development"
# The latest release's data tables carry the published national totals
tables_url <- "https://ncses.nsf.gov/pubs/nsf26304/assets/data-tables/nsf26304-data-tables-tables-excels.zip"
tables_page <- "https://ncses.nsf.gov/pubs/nsf26304"
cogr_page <- "https://www.cogr.edu/changes-federal-research-requirements-1991"

root <- getwd()
if (!file.exists(file.path(root, "pipeline", "build.R"))) stop("run from the repository root: Rscript pipeline/build.R")
raw_dir <- file.path(root, "pipeline", "raw")
out_dir <- file.path(root, "docs", "data")
db_path <- file.path(out_dir, "herd.duckdb")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(root, "pipeline", "validate.R"))
source(file.path(root, "pipeline", "metrics.R"))

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
tables_dir <- file.path(raw_dir, "nsf26304-tables")
unzip(fetch(tables_url, file.path(raw_dir, "nsf26304-tables.zip")), exdir = tables_dir, overwrite = TRUE)

if (file.exists(db_path)) invisible(file.remove(db_path))
con <- dbConnect(duckdb(), db_path)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# --- HERD microdata ------------------------------------------------------------
# Every column is read as text; NCSES files vary slightly by year and form.
# Most files are UTF-8; any that are not are Windows-1252 and get a UTF-8 copy.
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
    TRY_CAST(data AS DOUBLE)     AS value,
    NULLIF(status, '')           AS status,
    CASE
      WHEN questionnaire_no = '01.1' THEN 'code'
      WHEN questionnaire_no = '13'   THEN 'dollars'
      WHEN questionnaire_no = '15'   THEN 'headcount'
      WHEN questionnaire_no = '16'   THEN 'fte'
      ELSE 'thousands_usd'
    END                          AS unit
  FROM raw
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
table_path <- function(n) list.files(tables_dir, sprintf("tab%03d\\.xlsx$", n), full.names = TRUE, recursive = TRUE)

read_table2 <- function() {
  x <- read_excel(table_path(2), col_names = FALSE, .name_repair = "minimal")
  start <- which(x[[1]] == "All institutions")[1] + 1
  stop_at <- which(x[[1]] == "Short form institutionsa" | grepl("^Short form", x[[1]]))[1] - 1
  x <- x[start:stop_at, ]
  measures <- c("All R&D", "Federal government", "State and local government", "Institution funds",
                "Institution funds: institutionally financed research", "Institution funds: cost sharing",
                "Institution funds: unrecovered indirect costs", "Business", "Nonprofit organizations",
                "All other sources")
  do.call(rbind, lapply(seq_along(measures), function(j) data.frame(
    source_table = "NSF 26-304 Table 2", population = "All institutions", year = as.integer(x[[1]]),
    dimension = "Source of funds", measure = measures[j], value = as.numeric(x[[j + 1]])
  )))
}

read_table12 <- function() {
  x <- read_excel(table_path(12), col_names = FALSE, .name_repair = "minimal")
  years <- as.integer(unlist(x[4, -1]))
  start <- which(x[[1]] == "All institutions")[1] + 1
  stop_at <- which(x[[1]] == "Doctorate")[1] - 1
  x <- x[start:stop_at, ]
  do.call(rbind, lapply(seq_len(nrow(x)), function(i) data.frame(
    source_table = "NSF 26-304 Table 12", population = "Standard-form institutions", year = years,
    dimension = "Type of cost", measure = x[[1]][i], value = as.numeric(unlist(x[i, -1]))
  )))
}

published <- rbind(read_table2(), read_table12())
published <- published[!is.na(published$year) & !is.na(published$value), ]
# Table 12 repeats "Recovered" and "Unrecovered" under indirect costs; name them fully
published$measure[published$measure == "Recovered"] <- "Indirect costs: recovered"
published$measure[published$measure == "Unrecovered"] <- "Indirect costs: unrecovered"
published$unit <- "thousands_usd"
dbWriteTable(con, "national_published", published)

# --- COGR federal research requirements ----------------------------------------
# COGR publishes the cumulative count only as data labels on its Figure 1, not as a table
cogr <- data.frame(
  year = 1991:2024,
  cumulative_requirements = c(1, 2, 2, 5, 10, 11, 11, 11, 13, 16, 19, 22, 25, 29, 37, 39, 42, 51, 57,
                              69, 73, 82, 97, 102, 109, 119, 121, 129, 141, 157, 180, 211, 245, 270),
  source_note = "Data labels on COGR Figure 1, Changes in Federal Research Requirements Since 1991 (updated January 2025)"
)
dbWriteTable(con, "cogr_requirements", cogr)

# --- Carnegie Classification 2021 ----------------------------------------------
# Joined on IPEDS unit ID. The 2021 edition is held fixed across 2012-2024 so a
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
  SELECT count(DISTINCT g.inst_id) AS n, coalesce(sum(f.value), 0) / 1e3 AS rd_m
  FROM institution_groups g LEFT JOIN facts f ON f.inst_id = g.inst_id AND f.question_no = '01.g' AND f.year = 2024
  WHERE g.sector = 'Not classified'")
message(sprintf("Not classified: %d institutions, $%.0fM of FY 2024 R&D", unclassified$n, unclassified$rd_m))

# --- Provenance ----------------------------------------------------------------
sources <- rbind(
  data.frame(table_name = "facts, institutions", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("HERD Survey public microdata, FY %d-%d, standard and short form", first_year, last_year),
             url = microdata_page, files = paste(basename(files$url), collapse = "; ")),
  data.frame(table_name = "national_published", publisher = "NCSES, U.S. National Science Foundation",
             title = "HERD Survey FY 2024 data tables (NSF 26-304), Tables 2 and 12",
             url = tables_page, files = basename(tables_url)),
  data.frame(table_name = "cogr_requirements", publisher = "Council on Governmental Relations (COGR)",
             title = "Changes in Federal Research Requirements Since 1991, Figure 1 (updated January 2025)",
             url = cogr_page, files = "Figure 1 data labels, entered by hand"),
  data.frame(table_name = "carnegie_2021, institution_groups", publisher = "American Council on Education, Carnegie Classification",
             title = "Carnegie Classification of Institutions of Higher Education, 2021 update public data file",
             url = carnegie_page, files = basename(carnegie_url))
)
sources$built_on <- as.character(Sys.Date())
dbWriteTable(con, "sources", sources)

validate(con)
build_metrics(con)

# Parquet copies for downloads and for anyone who prefers files to a database
for (t in c("facts", "metrics", "measure_catalog", "institutions", "institution_groups", "national_published", "cogr_requirements", "sources")) {
  invisible(dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT parquet, COMPRESSION zstd)", t, file.path(out_dir, paste0(t, ".parquet")))))
}
invisible(dbExecute(con, "CHECKPOINT"))
for (f in list.files(out_dir, full.names = TRUE)) message(sprintf("wrote %-45s %6.1f MB", basename(f), file.size(f) / 1e6))
