# Data and sources (data.html)

## Source

All figures come from the public, institution-level microdata files that the National Center for Science and Engineering Statistics (NCSES) publishes for the HERD Survey: https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development. HERD Explorer reshapes and combines them but never changes a reported value.

## How the data were put together

- **Years**: FY {first_year} to FY {last_year}. All use the same survey design (introduced in FY 2010) and include the short-form survey, so national totals are complete.
- **Two survey forms**: institutions with $1 million or more in R&D answer the standard form; smaller ones answer a short form with fewer questions. Measures available only on the standard form are labeled that way, and their national totals leave out short-form institutions (about 0.1 percent of R&D).
- **Checked against NCSES**: each build compares 15 national totals in every year with the tables NCSES publishes (HERD FY {last_year} data tables, {tables_publication}, Tables 2 and 12). All match exactly; the build stops if any do not.
- **Not released by institution**: NCSES does not publish, for individual institutions, how institution funds split into institutionally financed research, cost sharing and unrecovered indirect costs, or how much indirect cost was recovered. Those appear only as national totals from the published tables.
- **Personnel** counts are released from FY 2022 onward.
- **Institution type** (sector) is the 2021 Carnegie Classification, held fixed for every year so a group means the same institutions throughout. HERD reporting units without a usable IPEDS ID (combined campuses, system offices, research institutes) are matched by a hand-checked crosswalk. Seven independent research institutes and three system offices, which Carnegie does not classify, are labeled by HERD Explorer.
- **Imputed values**: NCSES imputes some values for nonresponse (status i), about 0.1 to 0.4 percent of total R&D in a year. They are included as NCSES reports them, which is how the national totals match NCSES's tables. The survey-values download keeps NCSES's status code for every value. HERD Explorer itself does not impute, interpolate or fill in any values; a year an institution did not report is simply missing.
- **Dollars are nominal**, not adjusted for inflation. Stored values are in thousands of dollars; Explore's Table tab shows whole dollars.

## Measures

The Data & sources page has a searchable list of every measure with its definition, category, unit and coverage. Categories: Source of funds, Federal agency, Field of research, Field of research (federal), Type of cost, Subawards, Personnel, Other.

## Downloads (on data.html)

- Excel (XLSX), one row per institution and year, with a README, measure definitions and the source list
- CSV, one row per institution and year
- Every survey value, long format (CSV, zipped, 25 MB)
- Full database (DuckDB, 32 MB)
- Measures (Parquet) and survey values (Parquet)

Any table view built on Explore's Table tab can also be exported as CSV.

## Other sources

The Trends page's workload chart uses COGR's "Changes in Federal Research Requirements Since 1991" (Figure 1, updated {cogr_updated}), with data labels entered by hand.
