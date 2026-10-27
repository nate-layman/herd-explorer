# Named measures built from the raw survey cells.
#
# The standard and short forms number their questions differently (question 2 is
# foreign funds on one and field of research on the other), so every measure is
# defined here once, per form, and the site works from the `metrics` table instead
# of raw question numbers. `measure_catalog` documents each measure.

std_only <- "Standard-form institutions (R&D of $1 million or more)"
both <- "All institutions"

fields <- c(
  "Computer and information sciences", "Engineering", "Geosciences, atmospheric sciences, and ocean sciences",
  "Life sciences", "Mathematics and statistics", "Physical sciences", "Psychology", "Social sciences",
  "Other sciences", "Non-S&E"
)
agencies <- c(DOD = "Department of Defense", DOE = "Department of Energy", HHS = "Health and Human Services (incl. NIH)",
              NASA = "NASA", NSF = "National Science Foundation", USDA = "Department of Agriculture",
              `Other agencies` = "Other federal agencies")

slug <- function(x) gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(x)))

# Each measure: id, label, category, unit, coverage, definition, and the SQL that selects its cells.
# Selections return (year, inst_id, value) and are summed per institution-year.
m <- list()
add <- function(id, label, category, unit, coverage, definition, sql) {
  m[[length(m) + 1]] <<- list(id = id, label = label, category = category, unit = unit,
                             coverage = coverage, definition = definition, sql = sql)
}
cell <- function(where) sprintf("SELECT year, inst_id, value FROM facts WHERE %s", where)

sources <- c(`01.g` = "All R&D", `01.a` = "Federal government", `01.b` = "State and local government",
             `01.c` = "Business", `01.d` = "Nonprofit organizations", `01.e` = "Institution funds",
             `01.f` = "All other sources")
for (q in names(sources)) {
  add(paste0("source_", slug(sources[[q]])), sources[[q]], "Source of funds", "thousands_usd", both,
      if (q == "01.g") "Total R&D expenditures from all sources. Survey question 1, row g."
      else sprintf("R&D expenditures funded by %s. Survey question 1, row %s.", tolower(sources[[q]]), sub("01.", "", q, fixed = TRUE)),
      cell(sprintf("question_no = '%s'", q)))
}

for (a in names(agencies)) {
  add(paste0("agency_", slug(a)), agencies[[a]], "Federal agency", "thousands_usd", std_only,
      sprintf("Federally funded R&D expenditures from %s, all fields. Survey question 9, row k.", agencies[[a]]),
      cell(sprintf("form = 'standard' AND question_no = '09K' AND column_label = '%s'", a)))
}

for (f in fields) {
  lbl <- paste0(f, ", all")
  add(paste0("field_", slug(f)), f, "Field of research", "thousands_usd", both,
      sprintf("R&D expenditures in %s, all sources. Standard form: question 9 plus question 11; short form: question 2.", f),
      sprintf("%s UNION ALL %s",
              cell(sprintf("form = 'standard' AND (question_no LIKE '09%%' OR question_no LIKE '11%%') AND row_label = '%s' AND column_label = 'Total'", gsub("'", "''", lbl))),
              cell(sprintf("form = 'short' AND question_no LIKE '02.%%' AND row_label = '%s' AND column_label = 'Total'", gsub("'", "''", lbl)))))
  add(paste0("field_federal_", slug(f)), paste(f, "(federal)"), "Field of research, federal", "thousands_usd", both,
      sprintf("Federally funded R&D expenditures in %s. Standard form: question 9; short form: question 2.", f),
      sprintf("%s UNION ALL %s",
              cell(sprintf("form = 'standard' AND question_no LIKE '09%%' AND row_label = '%s' AND column_label = 'Total'", gsub("'", "''", lbl))),
              cell(sprintf("form = 'short' AND question_no LIKE '02.%%' AND row_label = '%s' AND column_label = 'Federal'", gsub("'", "''", lbl)))))
}

costs <- c(`12.a` = "Salaries, wages, and fringe benefits", `12.b1` = "Software, noncapitalized",
           `12.b2` = "Software, capitalized", `12.c` = "Capitalized equipment",
           `12.d` = "Passed through to subrecipients", `12.e` = "Other direct costs", `12.f` = "Indirect costs")
for (q in names(costs)) {
  add(paste0("cost_", slug(costs[[q]])), costs[[q]], "Type of cost", "thousands_usd", std_only,
      sprintf("R&D expenditures by type of cost: %s. Survey question 12, row %s.", costs[[q]], sub("12.", "", q, fixed = TRUE)),
      cell(sprintf("form = 'standard' AND question_no = '%s'", q)))
}
add("cost_direct", "Direct costs", "Type of cost", "thousands_usd", std_only,
    "All direct costs: survey question 12, rows a through e.",
    cell("form = 'standard' AND question_no IN ('12.a','12.b1','12.b2','12.c','12.d','12.e')"))

subs <- list(c("07.e", "subawards_received", "Received as a subrecipient", "question 7"),
             c("08.e", "subawards_passed", "Passed through to subrecipients", "question 8"))
for (s in subs) for (col in c("Total", "Federal", "Nonfederal")) {
  add(paste0(s[2], if (col == "Total") "" else paste0("_", tolower(col))),
      paste0(s[3], if (col == "Total") "" else paste0(" (", tolower(col), ")")), "Subawards", "thousands_usd", std_only,
      sprintf("R&D expenditures %s, %s funds, all partner types. Survey %s, row e.", tolower(s[3]), tolower(col), s[4]),
      cell(sprintf("form = 'standard' AND question_no = '%s' AND column_label = '%s'", s[1], col)))
}

add("foreign_total", "Foreign sources", "Other", "thousands_usd", std_only,
    "R&D expenditures funded by foreign sources (governments, businesses, nonprofits, universities). Survey question 2, total row.",
    cell("form = 'standard' AND question_no = '02.f'"))
add("medical_school", "Medical school R&D", "Other", "thousands_usd", std_only,
    "R&D expenditures at the institution's medical school. Survey question 4.",
    cell("form = 'standard' AND question_no = '04' AND row_label = 'Total'"))
add("clinical_trials", "Clinical trials", "Other", "thousands_usd", std_only,
    "R&D expenditures for clinical trials. Survey question 5, total.",
    cell("form = 'standard' AND question_no = '05' AND row_label = 'Total'"))

for (p in c("Total", "Researchers", "Technicians", "Support Staff")) {
  add(paste0("headcount_", slug(p)), paste("Headcount:", tolower(p)), "Personnel", "headcount", std_only,
      sprintf("Headcount of R&D personnel, %s. Survey question 15. Released FY 2022 onward.", tolower(p)),
      cell(sprintf("form = 'standard' AND question_no = '15' AND row_label = 'Total' AND column_label = '%s'", p)))
  add(paste0("fte_", slug(p)), paste("FTEs:", tolower(p)), "Personnel", "fte", std_only,
      sprintf("Full-time equivalents of R&D personnel, %s. Survey question 16. Released FY 2022 onward.", tolower(p)),
      cell(sprintf("form = 'standard' AND question_no = '16' AND row_label = 'Total' AND column_label = '%s'", p)))
}

build_metrics <- function(con) {
  catalog <- do.call(rbind, lapply(m, function(x) as.data.frame(x[setdiff(names(x), "sql")])))
  if (anyDuplicated(catalog$id)) stop("duplicate measure ids: ", paste(catalog$id[duplicated(catalog$id)], collapse = ", "))
  dbWriteTable(con, "measure_catalog", catalog, overwrite = TRUE)
  union <- paste(vapply(m, function(x) sprintf(
    "SELECT year, inst_id, '%s' AS measure_id, sum(value) AS value FROM (%s) GROUP BY year, inst_id", x$id, x$sql), ""),
    collapse = "\nUNION ALL\n")
  invisible(dbExecute(con, paste("CREATE OR REPLACE TABLE metrics AS SELECT * FROM (", union, ") WHERE value IS NOT NULL ORDER BY measure_id, inst_id, year")))
  empty <- dbGetQuery(con, "SELECT c.id FROM measure_catalog c LEFT JOIN metrics m ON m.measure_id = c.id GROUP BY c.id HAVING count(m.value) = 0")$id
  if (length(empty)) stop("measures with no data: ", paste(empty, collapse = ", "))
  # Internal consistency: fields add up to all R&D, agencies add up to federal (standard form)
  gaps <- dbGetQuery(con, "
    WITH t AS (
      SELECT year,
             sum(value) FILTER (WHERE measure_id = 'source_all_r_d')                                 AS all_rd,
             sum(value) FILTER (WHERE measure_id LIKE 'field\\_%' ESCAPE '\\' AND measure_id NOT LIKE 'field_federal_%') AS fields,
             sum(value) FILTER (WHERE measure_id = 'source_federal_government' AND inst_id IN (SELECT inst_id FROM facts WHERE form = 'standard' AND year = metrics.year)) AS fed_std,
             sum(value) FILTER (WHERE measure_id LIKE 'agency_%')                                     AS agencies
      FROM metrics GROUP BY year)
    SELECT * FROM t WHERE fields IS NULL OR agencies IS NULL OR abs(all_rd - fields) > 0.5 OR abs(fed_std - agencies) > 0.5")
  if (nrow(gaps)) { print(gaps); stop("metrics do not add up; see the years above") }
  message(sprintf("metrics: %d measures, %s rows", nrow(catalog),
                  format(dbGetQuery(con, "SELECT count(*) AS n FROM metrics")$n, big.mark = ",")))
}
