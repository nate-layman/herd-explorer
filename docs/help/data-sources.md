# About HERD (data.html)

The About HERD page (data.html) has two parts: the HERD Survey itself, then the Data & sources section (data.html#data) on how this site's data were built.

## The HERD Survey

The Higher Education Research and Development (HERD) Survey is the main source of data on research and development spending at U.S. colleges and universities. The National Center for Science and Engineering Statistics (NCSES), part of the U.S. National Science Foundation, runs it every year. NCSES's survey page: https://ncses.nsf.gov/surveys/higher-education-research-development.

- **Who reports**: public and private nonprofit colleges and universities in the United States and its territories that grant a bachelor's degree or higher and spend at least $150,000 on separately accounted-for R&D in their fiscal year. Each geographically separate campus headed by its own president or chancellor reports on its own. It is a census of these institutions, not a sample.
- **What counts as R&D**: creative and systematic work undertaken to increase knowledge (basic research, applied research and experimental development) in every field, not only science and engineering. Spending includes direct costs, indirect costs (recovered and unrecovered) and money passed through on subawards. It leaves out public service and outreach, curriculum development, training grants not for research, and construction or renovation.
- **What it asks**: R&D spending by source of funds, federal agency, field of research and type of cost, plus subawards and R&D personnel counts. Institutions with less than $1 million in R&D answer a short form with a few core questions.
- **When**: each institution reports for its own fiscal year (for most, July 1 to June 30). NCSES collects the data online over the following school year and publishes them roughly a year and a half after the fiscal year ends.
- **History**: HERD replaced the Survey of Research and Development Expenditures at Universities and Colleges (FY 1972 on) in FY 2010, adding questions and campus-level reporting. The short form began in FY 2012, which is why this site starts there.
- **Who uses it**: universities benchmarking against peers, NCSES's national statistics such as Science and Engineering Indicators, and rankings and classifications, including the R&D spending measure in the Carnegie research designations.

Things to keep in mind: institutions report from their own accounting records, so definitions (especially of institution funds) vary somewhat; NCSES imputes values for nonresponse (well under 1 percent of the national total); subaward money is counted twice in national totals, by the institution that passes it through and the one that spends it; R&D at university-managed FFRDCs is covered by a separate NCSES survey, not HERD.

# Data and sources (data.html#data)

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
- **Locations**: latitude and longitude come from the IPEDS directory file (HD) for the year closest to each institution's last HERD year. Units HERD reports without an IPEDS ID, and units IPEDS does not list (research institutes, military colleges), are placed by a hand-checked crosswalk from their street address. Locations are used only by the chart builder's map.
- **Dollars are nominal**, not adjusted for inflation. NCSES publishes HERD in thousands of dollars, and the database and downloads keep that unit so they match NCSES tables. The Trends, Compare and Explore pages show whole dollars (multiplied by 1,000); the Ask page converts in its answers.

## Measures

The About HERD page has a searchable list of every measure with its definition, category, unit and coverage. Categories: Source of funds, Federal agency, Field of research, Field of research (federal), Type of cost, Subawards, Personnel, Other.

## Downloads (on data.html)

- Excel (XLSX), one row per institution and year, with a README, measure definitions and the source list
- CSV, one row per institution and year
- Every survey value, long format (CSV, zipped, 25 MB)
- Full database (DuckDB, 42 MB)
- Measures (Parquet) and survey values (Parquet)

Any table view built on Explore's Table tab can also be exported as CSV.

## Other sources

The Trends page's workload chart uses COGR's "Changes in Federal Research Requirements Since 1991" (Figure 1, updated {cogr_updated}), with data labels entered by hand.
