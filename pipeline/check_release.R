# Is the next HERD survey year out? Checks whether NCSES has posted the microdata file for
# the year after release.yml's last_year. Prints what it found; with --github, also writes
# new_year=<year or empty> to $GITHUB_OUTPUT for the scheduled workflow.
#
# Usage: Rscript pipeline/check_release.R [--github]

source(file.path("pipeline", "release.R"))
r <- read_release()
next_year <- r$last_year + 1L
url <- sprintf("https://ncses.nsf.gov/821/assets/0/files/higher_education_r_and_d_%d.zip", next_year)
status <- tryCatch(attr(curlGetHeaders(url, verify = TRUE), "status"), error = function(e) NA_integer_)
found <- isTRUE(status == 200L)
if (found) {
  message(sprintf("FY %d microdata is out: %s\nSee RELEASING.md to update the site.", next_year, url))
} else {
  message(sprintf("FY %d microdata not posted yet (HTTP %s for %s).", next_year, status, url))
}
if ("--github" %in% commandArgs(TRUE)) {
  cat(sprintf("new_year=%s\n", if (found) next_year else ""), file = Sys.getenv("GITHUB_OUTPUT"), append = TRUE)
}
