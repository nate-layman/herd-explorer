# Projections: what they are

Trends and Compare can show projections to FY {projection_last_year} with a "Show projection to FY {projection_last_year}" switch.

A projection shows where past trends lead if they continue. It does not account for known upcoming changes, such as federal budget or policy shifts, and may not reflect what actually happens. Nor can it see survey revisions or an institution's own plans. Treat the shaded range, not the middle line, as the result.

## What is projected

Fiscal years {projection_first_year} to {projection_last_year}, for each institution, for every dollar measure: total R&D and each source of funds, each federal agency, each field of research, each type of cost, and subawards (51 measures at the last fit; About the model lists them). Personnel is not projected (released only from FY 2022). Any group (a type, a state, public or private, institutions you pick, the nation) is projected by adding up its institutions' simulated futures.

## Reading the chart

- The dotted middle line is the median of 200 simulated futures. Hover it to see the 80 percent range for each year.
- The darker band is the middle 80 percent of those futures, the lighter band the middle 90 percent.
- In testing on past years, about 80 percent and 90 percent of real outcomes fell inside those bands.
- Projections are not shown for "Share of national total" on Trends.

## Limitations

- Dollars are nominal, so the projections include inflation.
- {year_count} years is a short history; shocks larger than any seen since {first_year} are possible.
- Institutions entering or leaving the survey, mergers, or a measure dropping to zero are not projected.
- Announced policy changes that are not yet in the data (indirect cost rates, agency budgets) are not in the model.
- Testing used total R&D; the same model is applied to every other measure.

## Download

Every simulated future is published on Hugging Face as n8layman/herd-explorer-projections (CC BY 4.0), one Parquet file per measure, with the model and backtest tables.

For how the model works, see projection-model.md, or the About the model page (model.html).
