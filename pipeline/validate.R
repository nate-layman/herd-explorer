# Check microdata rollups against the national totals NCSES publishes.
#
# Table 2: R&D expenditures by source of funds, all institutions (standard and short form).
# Table 12: R&D expenditures by type of cost, standard-form institutions.
# Both are in thousands of dollars, the same unit as the microdata.

# Published measure -> questionnaire numbers that sum to it, and the forms they cover
checks <- rbind(
  data.frame(measure = c("All R&D", "Federal government", "State and local government", "Institution funds",
                         "Business", "Nonprofit organizations", "All other sources"),
             questions = c("01.g", "01.a", "01.b", "01.e", "01.c", "01.d", "01.f"),
             forms = "standard,short", source_table = "NSF 26-304 Table 2"),
  data.frame(measure = c("All R&D", "Direct costs", "Salaries, wages, and fringe benefits", "Software",
                         "Capitalized equipment", "Passed through to subrecipients", "Other direct costs",
                         "Indirect costs"),
             questions = c("01.g", "12.a,12.b1,12.b2,12.c,12.d,12.e", "12.a", "12.b1,12.b2", "12.c", "12.d", "12.e", "12.f"),
             forms = "standard", source_table = "NSF 26-304 Table 12")
)

validate <- function(con) {
  years <- dbGetQuery(con, "SELECT DISTINCT year FROM facts")$year
  problems <- character()
  checked <- 0L
  for (i in seq_len(nrow(checks))) {
    q <- strsplit(checks$questions[i], ",")[[1]]
    f <- strsplit(checks$forms[i], ",")[[1]]
    have <- dbGetQuery(con, sprintf(
      "SELECT year, sum(value) AS v FROM facts WHERE question_no IN (%s) AND form IN (%s) GROUP BY year",
      paste0("'", q, "'", collapse = ","), paste0("'", f, "'", collapse = ",")))
    want <- dbGetQuery(con, sprintf(
      "SELECT year, value AS v FROM national_published WHERE source_table = '%s' AND measure = '%s' AND year IN (%s)",
      checks$source_table[i], gsub("'", "''", checks$measure[i]), paste(years, collapse = ",")))
    if (nrow(want) == 0) {
      problems <- c(problems, sprintf("no published values found for '%s'", checks$measure[i]))
      next
    }
    m <- merge(want, have, by = "year", all.x = TRUE, suffixes = c("_published", "_microdata"))
    m$v_microdata[is.na(m$v_microdata)] <- 0
    checked <- checked + nrow(m)
    bad <- m[abs(m$v_microdata - m$v_published) > 0.5, ]
    if (nrow(bad)) problems <- c(problems, sprintf("%s, %s %d: microdata %s vs published %s", checks$source_table[i], checks$measure[i], bad$year,
                                                   format(bad$v_microdata, big.mark = ","), format(bad$v_published, big.mark = ",")))
  }
  if (length(problems)) {
    writeLines(problems)
    stop(sprintf("validation failed: %d of %d published totals do not match", length(problems), checked))
  }
  message(sprintf("validation passed: %d published totals match the microdata exactly", checked))
}
