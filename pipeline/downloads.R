# Download files for people who want the data outside the site:
#   herd_explorer_wide.csv / .xlsx  one row per institution and year, one column per measure
#   herd_explorer_survey_values.csv.zip  every reported survey value, long format
# Each carries the README text and the disclaimer.

download_readme <- function(built_on, first_year, last_year) paste(
  "HERD Explorer data download",
  "",
  sprintf("Source: NCSES Higher Education Research and Development (HERD) Survey public microdata, FY %d-%d,", first_year, last_year),
  "https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development",
  "Institution type (sector): Carnegie Classification of Institutions of Higher Education, 2021 update.",
  "Dollar values are in thousands of nominal dollars. Personnel values are people or full-time equivalents.",
  "Measure definitions: measure_catalog sheet, or https://nate-layman.github.io/herd-explorer/data.html",
  paste("Built on", built_on, "by HERD Explorer, https://github.com/nate-layman/herd-explorer"),
  "",
  "Disclaimer: HERD Explorer is an independent project. It is not an official product of NCSES or the U.S. National",
  "Science Foundation, and neither NCSES, NSF nor the University of Idaho endorses it. The data are provided as is,",
  "without warranty of any kind, and are not financial, budget, legal or investment advice. Check figures against the",
  "official NCSES tables before relying on them. Report errors at https://github.com/nate-layman/herd-explorer/issues",
  sep = "\n")

build_downloads <- function(con, out_dir, first_year, last_year) {
  dl <- file.path(out_dir, "downloads")
  dir.create(dl, showWarnings = FALSE)
  catalog <- dbGetQuery(con, "SELECT * FROM measure_catalog ORDER BY category, label")
  cols <- paste(sprintf("sum(value) FILTER (WHERE measure_id = '%s') AS \"%s\"", catalog$id, catalog$id), collapse = ",\n")
  wide <- dbGetQuery(con, paste0("
    WITH latest AS (SELECT * EXCLUDE (year) FROM institutions QUALIFY row_number() OVER (PARTITION BY inst_id ORDER BY year DESC) = 1)
    SELECT m.year, m.inst_id, l.name AS institution, l.state, g.sector, l.control, l.highest_degree,
           g.msi, l.hbcu, l.medical_school, g.land_grant, ", cols, "
    FROM metrics m JOIN latest l USING (inst_id) JOIN institution_groups g USING (inst_id)
    GROUP BY ALL ORDER BY institution, year"))
  readme <- download_readme(as.character(Sys.Date()), first_year, last_year)

  write.csv(wide, file.path(dl, "herd_explorer_wide.csv"), row.names = FALSE, na = "")
  writeLines(readme, file.path(dl, "README.txt"))
  writexl::write_xlsx(list(
    README = data.frame(README = strsplit(readme, "\n")[[1]]),
    data = wide,
    measure_catalog = catalog,
    sources = dbGetQuery(con, "SELECT * FROM sources")
  ), file.path(dl, "herd_explorer_wide.xlsx"))

  # Every survey value, zipped with the README
  raw_csv <- file.path(tempdir(), "herd_explorer_survey_values.csv")
  invisible(dbExecute(con, sprintf("COPY (SELECT * FROM facts ORDER BY year, inst_id, question_no) TO '%s' (HEADER)", raw_csv)))
  file.copy(file.path(dl, "README.txt"), file.path(tempdir(), "README.txt"), overwrite = TRUE)
  zip_path <- file.path(dl, "herd_explorer_survey_values.csv.zip")
  if (file.exists(zip_path)) file.remove(zip_path)
  utils::zip(zip_path, c(raw_csv, file.path(tempdir(), "README.txt")), flags = "-j9q")
  for (f in list.files(dl, full.names = TRUE)) message(sprintf("wrote downloads/%-38s %6.1f MB", basename(f), file.size(f) / 1e6))
}
