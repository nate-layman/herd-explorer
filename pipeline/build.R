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

# Download with the system curl, which resumes and retries on the slow NCSES servers (R's own
# downloader can stall there). Write to a temporary name and keep the file only when the whole
# download succeeds, so a cut-off download is never cached as if complete.
fetch <- function(url, dest) {
  if (!file.exists(dest)) {
    message("downloading ", url)
    part <- paste0(dest, ".part")
    status <- system2("curl", c("-fsL", "--retry", "8", "--retry-delay", "5",
                                "--speed-limit", "1000", "--speed-time", "120", "-C", "-",
                                "-A", shQuote("Mozilla/5.0 (herd-explorer build)"), "-o", shQuote(part), shQuote(url)))
    if (status != 0) { unlink(part); stop("download failed (curl exit ", status, "): ", url) }
    file.rename(part, dest)
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
dbWriteTable(con, "context_cogr_requirements", cogr)

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
dbWriteTable(con, "context_carnegie_2021", carnegie)

# Carnegie 2025 is a second, separate grouping. Its research designation (R1, R2, Research
# Colleges and Universities) uses fixed spending and doctorate thresholds, unlike 2021's
# relative indices, and it is no longer part of the basic classification.
carnegie25_url <- "https://carnegieclassifications.acenet.edu/wp-content/uploads/2025/04/2025-Public-Data-File.xlsx"
carnegie25_page <- "https://carnegieclassifications.acenet.edu/carnegie-classification/classification-methodology/2025-research-activity-designations/"
c25 <- read_excel(fetch(carnegie25_url, file.path(raw_dir, basename(carnegie25_url))), sheet = "data")
c25 <- c25[!is.na(c25$unitid), ]
carnegie_2025 <- data.frame(
  ipeds_unitid = as.character(c25$unitid),
  research_2025 = c(`1` = "R1", `2` = "R2", `3` = "Research Colleges and Universities")[as.character(c25$research2025)],
  institutional_2025 = c25$ic2025name
)
if (sum(carnegie_2025$research_2025 %in% c("R1", "R2")) < 300) stop("Carnegie 2025: expected about 326 R1 and R2 institutions; check the research2025 codes")
dbWriteTable(con, "context_carnegie_2025", carnegie_2025)

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
         coalesce(c.land_grant, false)                                  AS land_grant,
         c25.research_2025,
         c25.institutional_2025
  FROM ids
  LEFT JOIN carnegie_overrides o ON o.inst_id = ids.inst_id
  LEFT JOIN context_carnegie_2021 c ON c.ipeds_unitid = coalesce(o.carnegie_unitid, ids.ipeds_unitid)
  LEFT JOIN context_carnegie_2025 c25 ON c25.ipeds_unitid = coalesce(o.carnegie_unitid, ids.ipeds_unitid)
"))
bad <- dbGetQuery(con, "SELECT o.inst_id, o.herd_name FROM carnegie_overrides o
                        LEFT JOIN context_carnegie_2021 c ON c.ipeds_unitid = o.carnegie_unitid
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
# IPEDS serves the 2023 and later collections from complete-data-files; the older datacenter
# path has stale copies of those. Try the new path first, and use the revised (_rv) file when
# a zip has one. Returns NULL when the file is not posted yet.
ipeds_urls <- c("https://nces.ed.gov/ipeds/complete-data-files/%s.zip", "https://nces.ed.gov/ipeds/datacenter/data/%s.zip")
ipeds_used <- character()
read_ipeds <- function(file) {
  zip <- file.path(raw_dir, paste0(file, ".zip"))
  for (u in ipeds_urls) {
    if (file.exists(zip)) break
    tryCatch(fetch(sprintf(u, file), zip), error = function(e) unlink(zip))
  }
  if (!file.exists(zip)) return(NULL)
  csvs <- grep("\\.csv$", unzip(zip, list = TRUE)$Name, value = TRUE, ignore.case = TRUE)
  csv <- if (length(csvs) > 1) grep("_rv\\.csv$", csvs, value = TRUE, ignore.case = TRUE) else csvs
  if (length(csv) != 1) stop(file, ".zip: expected one CSV or one _rv CSV, found ", paste(csvs, collapse = ", "))
  exdir <- file.path(raw_dir, file)
  unzip(zip, files = csv, exdir = exdir, overwrite = TRUE)
  lines <- readLines(file.path(exdir, csv), warn = FALSE)
  if (!all(validUTF8(lines))) lines <- iconv(lines, from = "CP1252", to = "UTF-8")
  x <- read.csv(text = lines, colClasses = "character", check.names = FALSE, na.strings = c("", "."), strip.white = TRUE)
  names(x) <- toupper(trimws(sub("^﻿", "", names(x))))
  ipeds_used <<- c(ipeds_used, file)
  x
}
hd_page <- "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx?year=-1&sid=HD"
read_hd <- function(y) {
  x <- read_ipeds(sprintf("HD%d", y))
  if (is.null(x)) { message("IPEDS HD", y, " is not available yet; using the other years"); return(NULL) }
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

# State names to two-letter codes, for the Census and BEA files
abbr <- c(setNames(state.abb, state.name), `District of Columbia` = "DC", `Puerto Rico` = "PR")

# --- IPEDS IDs for institution-level context ---------------------------------------
# One IPEDS unit ID per HERD institution, chosen the same way as for locations: the location
# crosswalk, then HERD's own ID, then the Carnegie crosswalk. IPEDS and graduate-survey values
# attach to a HERD institution only in years when no other reporting HERD unit shares its ID
# (e.g. two CUNY units), so nothing is counted twice.
invisible(dbExecute(con, "
  CREATE TABLE institution_unitids AS
  WITH ids AS (SELECT inst_id, max(ipeds_unitid) AS ipeds_unitid FROM institutions GROUP BY inst_id)
  SELECT ids.inst_id, coalesce(o.ipeds_unitid, ids.ipeds_unitid, g.carnegie_unitid) AS unitid
  FROM ids JOIN institution_groups g USING (inst_id)
  LEFT JOIN location_overrides o USING (inst_id)
  WHERE coalesce(o.ipeds_unitid, ids.ipeds_unitid, g.carnegie_unitid) IS NOT NULL
  ORDER BY inst_id
"))
invisible(dbExecute(con, "
  CREATE TEMP TABLE unitid_owner AS
  SELECT u.unitid, i.year, any_value(u.inst_id) AS inst_id
  FROM institution_unitids u JOIN institutions i USING (inst_id)
  GROUP BY ALL HAVING count(DISTINCT u.inst_id) = 1
"))

# --- IPEDS faculty, enrollment and finance -------------------------------------------
# Per institution and HERD fiscal year, from IPEDS files aligned to that year:
#   ft_instructional_staff  S{Y-1}_IS, all full-time instructional staff (SISCAT 1), as of November 1 of Y-1.
#                           FY 2012 is empty: the 2011 staff files use a different layout with no matching total.
#   enrollment_12mo         EFFY{Y}, 12-month unduplicated headcount, all students (EFFYLEV 1), July Y-1 to June Y
#   fte_students            EFIA{Y}, reported FTE: undergraduate + graduate + doctor's professional practice
#   research_doctorates     C{Y}_A, doctor's degrees, research/scholarship (AWLEVEL 17), all fields (CIPCODE 99),
#                           first majors, July Y-1 to June Y: the doctorate count in the Carnegie research designations
#   research_expenses,      F{Y-1}{Y}_F1A (public, GASB: F1C021, F1D02, F1H02) or _F2 (private nonprofit, FASB:
#   total_expenses,         F2E021, F2B02, F2H02), fiscal year ending in Y. Whole dollars, as IPEDS reports them.
#   endowment               Endowment is the value of endowment assets at the end of the fiscal year, including foundations.
# IPEDS research expenses are a functional expense category, not the HERD R&D definition.
num <- function(v) suppressWarnings(as.numeric(v))
yy <- function(y) sprintf("%02d", y %% 100)
ipeds_year <- function(y) {
  staff <- if (y > 2012) read_ipeds(sprintf("S%d_IS", y - 1))  # no S2011_IS; see above
  if (!is.null(staff)) staff <- with(staff[trimws(staff$SISCAT) == "1", ], data.frame(unitid = UNITID, ft_instructional_staff = num(HRTOTLT)))
  effy <- read_ipeds(sprintf("EFFY%d", y))
  if (!is.null(effy)) effy <- with(effy[trimws(effy$EFFYLEV) == "1", ], data.frame(unitid = UNITID, enrollment_12mo = num(EFYTOTLT)))
  efia <- read_ipeds(sprintf("EFIA%d", y))
  if (!is.null(efia)) efia <- with(efia, data.frame(unitid = UNITID,
    fte_students = rowSums(cbind(num(FTEUG), num(FTEGD), num(FTEDPP)), na.rm = TRUE)))
  comp <- read_ipeds(sprintf("C%d_A", y))
  if (!is.null(comp)) comp <- with(comp[trimws(comp$CIPCODE) == "99" & trimws(comp$MAJORNUM) == "1" & as.integer(comp$AWLEVEL) == 17, ],
                                   data.frame(unitid = UNITID, research_doctorates = num(CTOTALT)))
  f1 <- read_ipeds(sprintf("F%s%s_F1A", yy(y - 1), yy(y)))
  f2 <- read_ipeds(sprintf("F%s%s_F2", yy(y - 1), yy(y)))
  fin <- rbind(
    if (!is.null(f1)) data.frame(unitid = f1$UNITID, research_expenses = num(f1$F1C021), total_expenses = num(f1$F1D02), endowment = num(f1$F1H02)),
    if (!is.null(f2)) data.frame(unitid = f2$UNITID, research_expenses = num(f2$F2E021), total_expenses = num(f2$F2B02), endowment = num(f2$F2H02)))
  parts <- Filter(Negate(is.null), list(staff, effy, efia, comp, fin))
  if (!length(parts)) return(NULL)
  out <- Reduce(function(a, b) merge(a, b, by = "unitid", all = TRUE), parts)
  for (col in c("ft_instructional_staff", "enrollment_12mo", "fte_students", "research_doctorates", "research_expenses", "total_expenses", "endowment"))
    if (!col %in% names(out)) out[[col]] <- NA_real_
  out$year <- y
  out
}
ip <- do.call(rbind, lapply(first_year:last_year, ipeds_year))
dbWriteTable(con, "ipeds_raw", ip, temporary = TRUE)
invisible(dbExecute(con, "
  CREATE TABLE context_ipeds AS
  SELECT o.inst_id, p.year, p.ft_instructional_staff, p.enrollment_12mo, p.fte_students, p.research_doctorates,
         p.research_expenses, p.total_expenses, p.endowment
  FROM ipeds_raw p JOIN unitid_owner o ON o.unitid = p.unitid AND o.year = p.year
  ORDER BY o.inst_id, p.year
"))
ipeds_cov <- dbGetQuery(con, sprintf("
  SELECT count(*) FILTER (WHERE ft_instructional_staff IS NOT NULL) AS staff, count(*) FILTER (WHERE total_expenses IS NOT NULL) AS fin,
         (SELECT count(*) FROM institutions WHERE year = %1$d) AS herd
  FROM context_ipeds WHERE year = %1$d", last_year))
message(sprintf("IPEDS: FY %d has faculty for %d and finance for %d of %d HERD institutions",
                last_year, ipeds_cov$staff, ipeds_cov$fin, ipeds_cov$herd))

# --- NCSES graduate students and postdocs (GSS) -------------------------------------
# Institution totals from the GSS public microdata, one row per school and field. The file
# covers science, engineering and health fields only; summing every row gives NCSES's
# published national totals. GSS counts are a fall headcount (fall 2024 for 2024).
# Series breaks: the 2014 frame added about 150 institutions, and the 2017 redesign changed
# the field taxonomy (the 2017 file here is the new design).
gss_url <- "https://ncses.nsf.gov/826/assets/0/files/graduate_students_postdocs_%d.zip"
gss_page <- "https://ncses.nsf.gov/explore-data/microdata/graduate-students-postdocs-s-e"
read_gss <- function(y) {
  zip <- file.path(raw_dir, sprintf("graduate_students_postdocs_%d.zip", y))
  got <- tryCatch(fetch(sprintf(gss_url, y), zip), error = function(e) { unlink(zip); conditionMessage(e) })
  if (!file.exists(zip)) {
    # Only the newest year may be missing: GSS is released on its own schedule
    if (y < last_year) stop("GSS ", y, " did not download: ", got)
    message("GSS ", y, " is not available yet; graduate_students ends a year early")
    return(NULL)
  }
  sas <- grep(sprintf("^gss%d_code\\.sas7bdat$", y), unzip(zip, list = TRUE)$Name, value = TRUE, ignore.case = TRUE)
  if (length(sas) != 1) stop(basename(zip), ": expected one gss", y, "_code.sas7bdat")
  exdir <- file.path(raw_dir, sprintf("gss%d", y))
  unzip(zip, files = sas, exdir = exdir, overwrite = TRUE)
  x <- haven::read_sas(file.path(exdir, sas), col_select = tidyselect::any_of(c(
    "UNITID", "ft_tot_all_races_v", "pt_tot_all_races_v", "pd_tot_all_races_v", "nfr_tot_all_v", "nfr_tot_all_degr_v")))
  nfr <- if ("nfr_tot_all_v" %in% names(x)) x$nfr_tot_all_v else x$nfr_tot_all_degr_v
  data.frame(unitid = as.character(x$UNITID), year = y,
             grad = x$ft_tot_all_races_v + x$pt_tot_all_races_v, pd = x$pd_tot_all_races_v, nfr = nfr)
}
gss <- do.call(rbind, lapply(first_year:last_year, read_gss))
dbWriteTable(con, "gss_raw", gss, temporary = TRUE)
invisible(dbExecute(con, "
  CREATE TABLE context_graduate_students AS
  SELECT o.inst_id, g.year, sum(g.grad) AS grad_students, sum(g.pd) AS postdocs, sum(g.nfr) AS nonfaculty_researchers
  FROM gss_raw g JOIN unitid_owner o ON o.unitid = g.unitid AND o.year = g.year
  GROUP BY ALL ORDER BY o.inst_id, g.year
"))
cov <- dbGetQuery(con, "
  SELECT g.year, sum(g.grad) AS all_grad, sum(g.grad) FILTER (WHERE o.inst_id IS NOT NULL) AS matched
  FROM gss_raw g LEFT JOIN unitid_owner o ON o.unitid = g.unitid AND o.year = g.year
  GROUP BY ALL ORDER BY g.year")
message(sprintf("Graduate students: %d-%d; share of GSS graduate students attached to a HERD institution: %s",
                min(cov$year), max(cov$year), paste(sprintf("%d %.0f%%", cov$year, 100 * cov$matched / cov$all_grad), collapse = ", ")))

# --- NSF EPSCoR eligibility ----------------------------------------------------------
# Jurisdictions eligible for NSF EPSCoR research infrastructure (RII) awards by NSF fiscal
# year, typed from NSF's yearly eligibility tables into pipeline/epscor_eligibility.csv.
epscor <- read.csv(file.path(root, "pipeline", "epscor_eligibility.csv"), colClasses = c("integer", "character"))
if (any(!epscor$state %in% c(unname(abbr), "GU", "VI", "AS"))) stop("epscor_eligibility.csv: unknown state codes")
if (max(epscor$fiscal_year) < last_year)
  warning(sprintf("epscor_eligibility.csv ends in FY %d, before %d; add the newer years from NSF", max(epscor$fiscal_year), last_year), call. = FALSE)
dbWriteTable(con, "context_epscor_eligibility", epscor)

# --- State population ----------------------------------------------------------
# Census Bureau resident population estimates for July 1 of each year, from the latest
# vintage (release.yml). Covers the 50 states, DC and Puerto Rico; the Bureau does not
# estimate American Samoa, Guam or the U.S. Virgin Islands, so they have no rows.
pop_raw <- read.csv(fetch(release$population$csv, file.path(raw_dir, basename(release$population$csv))),
                    colClasses = "character", check.names = FALSE)
pop_raw <- pop_raw[pop_raw$SUMLEV == "040", ]
if (any(is.na(abbr[pop_raw$NAME]))) stop("unrecognized state names in ", basename(release$population$csv), ": ",
                                         paste(pop_raw$NAME[is.na(abbr[pop_raw$NAME])], collapse = "; "))
pop_cols <- grep("^POPESTIMATE\\d{4}$", names(pop_raw), value = TRUE)
state_population <- do.call(rbind, lapply(pop_cols, function(col) data.frame(
  state = unname(abbr[pop_raw$NAME]), state_name = pop_raw$NAME,
  year = as.integer(sub("POPESTIMATE", "", col)), population = as.numeric(pop_raw[[col]]),
  vintage = release$population$vintage)))
if (nrow(state_population) != 52 * length(pop_cols) || anyNA(state_population$population))
  stop("state population: expected 52 states, DC and PR with a value in every year")
if (max(state_population$year) != release$population$vintage)
  stop("state population file ends in ", max(state_population$year), ", not vintage ", release$population$vintage)
state_population <- state_population[order(state_population$state, state_population$year), ]
dbWriteTable(con, "context_state_population", state_population)
message(sprintf("State population: %d (states, DC and PR), %d-%d (vintage %d)", length(unique(state_population$state)),
                min(state_population$year), max(state_population$year), release$population$vintage))

# --- GDP price index ------------------------------------------------------------
# BEA's GDP implicit price deflator by calendar year (NIPA Table 1.1.9, line 1; series A191RD),
# the index NCSES uses for HERD's constant-dollar figures, from BEA's annual NIPA flat file.
# HERD values stay nominal; the site divides by this index to show real dollars.
deflator_url <- "https://apps.bea.gov/national/Release/TXT/NipaDataA.txt"
deflator_page <- "https://apps.bea.gov/iTable/?reqid=19&step=2&isuri=1&categories=survey"
nipa <- read.csv(fetch(deflator_url, file.path(raw_dir, "NipaDataA.txt")), colClasses = "character", check.names = FALSE)
nipa <- nipa[nipa[[1]] == "A191RD", ]
gdp_deflator <- data.frame(year = as.integer(nipa$Period), value = as.numeric(gsub(",", "", nipa$Value)))
gdp_deflator <- gdp_deflator[gdp_deflator$year >= first_year, ]
# BEA rebases the index every few years; the base is the year whose value is 100
gdp_deflator$base_year <- gdp_deflator$year[which.min(abs(gdp_deflator$value - 100))]
if (!all(first_year:last_year %in% gdp_deflator$year))
  stop("GDP price index is missing years in ", first_year, "-", last_year)
dbWriteTable(con, "context_gdp_deflator", gdp_deflator)
message(sprintf("GDP price index: %d-%d, %d = 100", min(gdp_deflator$year), max(gdp_deflator$year), gdp_deflator$base_year[1]))

# --- State GDP -------------------------------------------------------------------
# BEA's current-dollar GDP by state (SAGDP1, line 3), in millions of dollars; multiplied by
# 1,000,000 here so it is in whole dollars like everything else. BEA does not include Puerto Rico.
sagdp_url <- "https://apps.bea.gov/regional/zip/SAGDP.zip"
sagdp_page <- "https://apps.bea.gov/regional/downloadzip.htm"
sagdp_zip <- fetch(sagdp_url, file.path(raw_dir, "SAGDP.zip"))
sagdp_csv <- grep("^SAGDP1__ALL_AREAS_\\d{4}_\\d{4}\\.csv$", unzip(sagdp_zip, list = TRUE)$Name, value = TRUE)
if (length(sagdp_csv) != 1) stop("SAGDP.zip: expected one SAGDP1__ALL_AREAS file, found ", length(sagdp_csv))
unzip(sagdp_zip, files = sagdp_csv, exdir = file.path(raw_dir, "SAGDP"), overwrite = TRUE)
sg <- read.csv(file.path(raw_dir, "SAGDP", sagdp_csv), colClasses = "character", check.names = FALSE, strip.white = TRUE)
sg <- sg[trimws(sg$LineCode) == "3" & sg$GeoName %in% names(abbr), ]
year_cols <- grep("^\\d{4}$", names(sg), value = TRUE)
year_cols <- year_cols[as.integer(year_cols) >= first_year]
state_gdp <- do.call(rbind, lapply(year_cols, function(y) data.frame(
  state = unname(abbr[sg$GeoName]), year = as.integer(y),
  gdp = suppressWarnings(as.numeric(sg[[y]])) * 1e6)))
state_gdp <- state_gdp[!is.na(state_gdp$gdp), ]
state_gdp <- state_gdp[order(state_gdp$state, state_gdp$year), ]
if (length(unique(state_gdp$state)) != 51) stop("state GDP: expected 50 states and DC, found ", length(unique(state_gdp$state)))
if (max(state_gdp$year) < last_year) stop("state GDP ends in ", max(state_gdp$year), ", before ", last_year)
dbWriteTable(con, "context_state_gdp", state_gdp)
message(sprintf("State GDP: %d-%d", min(state_gdp$year), max(state_gdp$year)))

herd <- "HERD Survey (NCSES)"; other <- "Not HERD: other publisher"

# --- Provenance ----------------------------------------------------------------
sources <- rbind(
  data.frame(table_name = "facts, institutions", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("HERD Survey public microdata, FY %d-%d, standard and short form", first_year, last_year),
             url = microdata_page, files = paste(basename(files$url), collapse = "; ")),
  data.frame(table_name = "national_published", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("HERD Survey FY %d data tables (%s), Tables %d and %d", last_year, tables_label, funds_table, cost_table),
             url = tables_page, files = basename(tables_url)),
  data.frame(table_name = "context_cogr_requirements", publisher = "Council on Governmental Relations (COGR)",
             title = sprintf("Changes in Federal Research Requirements Since 1991, Figure 1 (updated %s)", release$cogr$updated),
             url = cogr_page, files = "Figure 1 data labels, entered by hand"),
  data.frame(table_name = "context_carnegie_2021, institution_groups", publisher = "American Council on Education, Carnegie Classification",
             title = "Carnegie Classification of Institutions of Higher Education, 2021 update public data file",
             url = carnegie_page, files = basename(carnegie_url)),
  data.frame(table_name = "context_carnegie_2025, institution_groups", publisher = "American Council on Education, Carnegie Classification",
             title = "Carnegie Classification of Institutions of Higher Education, 2025 public data file: research activity designations and institutional classification",
             url = carnegie25_page, files = basename(carnegie25_url)),
  data.frame(table_name = "context_ipeds", publisher = "NCES, U.S. Department of Education",
             title = sprintf("IPEDS Human Resources (S_IS), 12-Month Enrollment (EFFY), Instructional Activity (EFIA), Completions (C_A) and Finance (F1A, F2), FY %d-%d", min(ip$year), max(ip$year)),
             url = "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx", files = paste(grep("^HD", ipeds_used, invert = TRUE, value = TRUE), collapse = "; ")),
  data.frame(table_name = "context_graduate_students", publisher = "NCSES, U.S. National Science Foundation",
             title = sprintf("Survey of Graduate Students and Postdoctorates in Science and Engineering (GSS) public microdata, %d-%d", min(gss$year), max(gss$year)),
             url = gss_page, files = paste(sprintf("graduate_students_postdocs_%d.zip", sort(unique(gss$year))), collapse = "; ")),
  data.frame(table_name = "context_epscor_eligibility", publisher = "U.S. National Science Foundation",
             title = sprintf("EPSCoR eligibility tables, FY %d-%d, entered by hand", min(epscor$fiscal_year), max(epscor$fiscal_year)),
             url = "https://www.nsf.gov/funding/initiatives/epscor/epscor-criteria-eligibility", files = "pipeline/epscor_eligibility.csv"),
  data.frame(table_name = "institution_locations", publisher = "NCES, U.S. Department of Education",
             title = sprintf("IPEDS Institutional Characteristics, directory information (HD), %d-%d: latitude and longitude", min(hd$year), max(hd$year)),
             url = hd_page, files = paste(sprintf("HD%d.zip", sort(unique(hd$year))), collapse = "; ")),
  data.frame(table_name = "context_state_population", publisher = "U.S. Census Bureau",
             title = sprintf("Annual Estimates of the Resident Population for the United States, Regions, States, District of Columbia, and Puerto Rico, Vintage %d (July 1, %d-%d)",
                             release$population$vintage, min(state_population$year), max(state_population$year)),
             url = release$population$page, files = basename(release$population$csv)),
  data.frame(table_name = "context_gdp_deflator", publisher = "U.S. Bureau of Economic Analysis",
             title = sprintf("National Income and Product Accounts, Table 1.1.9, Implicit Price Deflators for GDP, line 1 (series A191RD), %d = 100", gdp_deflator$base_year[1]),
             url = deflator_page, files = "NipaDataA.txt"),
  data.frame(table_name = "context_state_gdp", publisher = "U.S. Bureau of Economic Analysis",
             title = "SAGDP1, State annual gross domestic product summary: current-dollar GDP",
             url = sagdp_page, files = paste("SAGDP.zip:", sagdp_csv))
)
sources$origin <- ifelse(sources$table_name %in% c("facts, institutions", "national_published"), herd, other)
sources$built_on <- as.character(Sys.Date())
dbWriteTable(con, "sources", sources)

# Every year in release.yml must be in the microdata, and no others
got <- dbGetQuery(con, "SELECT DISTINCT year FROM facts ORDER BY year")$year
if (!identical(as.integer(got), first_year:last_year))
  stop("microdata years ", paste(range(got), collapse = "-"), " do not match release.yml ", first_year, "-", last_year)

validate(con, funds_source, cost_source)
build_metrics(con)

# Ranks and shares computed from HERD metrics: computed by HERD Explorer, not published by NCSES.
# Each measure and year ranks the institutions that reported it; ties share a rank. A measure
# asked only on the standard form ranks only standard-form institutions.
invisible(dbExecute(con, "
  CREATE TABLE herd_ranks AS
  SELECT m.year, m.inst_id, m.measure_id,
         CAST(rank() OVER (PARTITION BY m.measure_id, m.year ORDER BY m.value DESC) AS INTEGER)          AS rank_national,
         CAST(count(*) OVER (PARTITION BY m.measure_id, m.year) AS INTEGER)                               AS n_national,
         CAST(rank() OVER (PARTITION BY m.measure_id, m.year, i.state ORDER BY m.value DESC) AS INTEGER) AS rank_state,
         CAST(count(*) OVER (PARTITION BY m.measure_id, m.year, i.state) AS INTEGER)                      AS n_state,
         m.value / nullif(sum(m.value) OVER (PARTITION BY m.measure_id, m.year), 0)                        AS share_national
  FROM metrics m JOIN institutions i ON i.inst_id = m.inst_id AND i.year = m.year
  ORDER BY m.measure_id, m.year, rank_national
"))

# What is HERD and what is not: every table's origin, for the site, the Ask page and the downloads
herd <- "HERD Survey (NCSES)"; computed <- "Computed from HERD by HERD Explorer"; other <- "Not HERD: other publisher"
table_catalog <- rbind(
  data.frame(table_name = "facts", origin = herd, description = "Every HERD survey value as NCSES released it (dollars converted from thousands to whole dollars)"),
  data.frame(table_name = "institutions", origin = herd, description = "Institution names and attributes as reported in the HERD microdata"),
  data.frame(table_name = "metrics", origin = herd, description = "HERD survey values combined into named measures (sums of reported cells, see measure_catalog)"),
  data.frame(table_name = "measure_catalog", origin = herd, description = "Definitions of the HERD measures in metrics"),
  data.frame(table_name = "national_published", origin = herd, description = "National totals from the NCSES HERD data tables"),
  data.frame(table_name = "herd_ranks", origin = computed, description = "National and in-state rank and national share of each HERD measure, by year"),
  data.frame(table_name = "institution_unitids", origin = computed, description = "The IPEDS ID HERD Explorer uses to link each HERD institution to IPEDS and GSS"),
  data.frame(table_name = "institution_groups", origin = other, description = "Carnegie 2021 sector and 2025 research designation, MSI, HSI, tribal and land-grant flags (Carnegie); ten units labeled by HERD Explorer"),
  data.frame(table_name = "institution_locations", origin = other, description = "Latitude and longitude (IPEDS directory files; some entered by HERD Explorer)"),
  data.frame(table_name = "context_carnegie_2021", origin = other, description = "Carnegie 2021 basic classification and flags, the source of the sector groups"),
  data.frame(table_name = "context_carnegie_2025", origin = other, description = "Carnegie 2025 research designations and institutional classification"),
  data.frame(table_name = "context_cogr_requirements", origin = other, description = "COGR's count of federal research requirements"),
  data.frame(table_name = "context_state_population", origin = other, description = "Census Bureau state population estimates"),
  data.frame(table_name = "context_gdp_deflator", origin = other, description = "BEA GDP implicit price deflator"),
  data.frame(table_name = "context_state_gdp", origin = other, description = "BEA GDP by state"),
  data.frame(table_name = "context_epscor_eligibility", origin = other, description = "NSF EPSCoR eligible jurisdictions by fiscal year"),
  data.frame(table_name = "context_ipeds", origin = other, description = "IPEDS faculty, enrollment, research doctorates, expenses and endowment by institution and year"),
  data.frame(table_name = "context_graduate_students", origin = other, description = "NCSES GSS graduate students, postdocs and non-faculty researchers by institution and year")
)
uncatalogued <- setdiff(grep("^context_", dbListTables(con), value = TRUE), table_catalog$table_name)
if (length(uncatalogued)) stop("add these tables to table_catalog with their origin: ", paste(uncatalogued, collapse = ", "))
missing_tables <- setdiff(table_catalog$table_name, dbListTables(con))
if (length(missing_tables)) stop("table_catalog lists tables the build did not write: ", paste(missing_tables, collapse = ", "))
dbWriteTable(con, "table_catalog", table_catalog)
build_downloads(con, out_dir, first_year, last_year)
jsonlite::write_json(c(site_meta(release), built_on = as.character(Sys.Date())),
                     file.path(out_dir, "meta.json"), auto_unbox = TRUE, pretty = TRUE)
message("wrote meta.json")

# Parquet copies for downloads and for anyone who prefers files to a database
for (t in c("facts", "metrics", "measure_catalog", "herd_ranks", "institutions", "institution_groups", "institution_locations", "institution_unitids", "national_published", "table_catalog",
           grep("^context_", dbListTables(con), value = TRUE), "sources")) {
  invisible(dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT parquet, COMPRESSION zstd)", t, file.path(out_dir, paste0(t, ".parquet")))))
}
invisible(dbExecute(con, "CHECKPOINT"))
for (f in list.files(out_dir, pattern = "\\.(parquet|duckdb)$", full.names = TRUE)) message(sprintf("wrote %-45s %6.1f MB", basename(f), file.size(f) / 1e6))
