---
license: cc-by-4.0
pretty_name: HERD Explorer projections
tags:
  - higher-education
  - research-administration
  - forecasting
  - herd-survey
size_categories:
  - 10M<n<100M
---

# HERD Explorer projections

Simulated projections of research and development spending at U.S. colleges and universities, FY 2025 to FY 2029, for every dollar measure in [HERD Explorer](https://nate-layman.github.io/herd-explorer/). The site reads these files directly in the browser.

**A projection shows where past trends lead if they continue.** It does not account for known upcoming changes, such as federal budget or policy shifts, and may not reflect what actually happens. Nor can it see survey revisions or an institution's own plans.

## Files

- `<measure_id>.parquet`: 200 simulated futures per institution and year. Columns: `inst_id` (NCSES HERD institution ID), `year`, `draw` (1 to 200), `value` (thousands of nominal dollars). Rows are sorted by institution. To get a range for any group of institutions, add the institutions' values within each draw, then take percentiles across draws.
- `by_group/<measure_id>.parquet`: the same draws already summed for every group the site shows (`split` is empty for the national total, or `sector`, `control`, `state`, `msi`, `hbcu`, `medical_school`, `land_grant`; `grp` is the group). Institutions the model did not project are included at their last reported value.
- `by_institution/inst_id=<id>/data_0.parquet`: every measure's draws for one institution (`measure_id`, `year`, `draw`, `value`).
- `model_info.parquet`: one row per measure, with whether it was modeled, the reason if not, and fitted parameters.
- `backtest*.parquet`: how the model scored against past years (CRPS and interval coverage), overall, by institution size, and for each candidate interval width.

Measure definitions are in the `measure_catalog` table of the HERD Explorer database.

## Method

A hierarchical growth model fit with the R package mgcv: year-to-year growth in log spending, with typical growth by institution type (2021 Carnegie Classification), state and institution random effects, shared year and year-by-type shocks, and noise that depends on institution size. Chosen over a naive baseline and a model of spending levels by rolling backtests. Full description: [About the model](https://nate-layman.github.io/herd-explorer/model.html). Code: [model/fit.R](https://github.com/nate-layman/herd-explorer/blob/main/model/fit.R).

## Source data

NCSES [Higher Education Research and Development Survey](https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development) public microdata, FY 2012 to FY 2024.

## Disclaimer

HERD Explorer is an independent project. It is not an official product of NCSES or the U.S. National Science Foundation, and neither NCSES, NSF nor the University of Idaho endorses it. These projections are provided as is, without warranty of any kind, and are not financial, budget, legal or investment advice. Report problems at https://github.com/nate-layman/herd-explorer/issues

## Citation

Layman, N. HERD Explorer. University of Idaho, AI4RA. https://github.com/nate-layman/herd-explorer

This material is based upon work supported by the U.S. National Science Foundation under award 2427549.
