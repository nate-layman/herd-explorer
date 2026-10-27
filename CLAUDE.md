# CLAUDE.md, HERD Explorer

## Project

Browser-based explorer for the NCSES HERD Survey, FY 2012 to FY 2024. Static site on GitHub Pages from `docs/`. See PLAN.md for the design and the decisions behind it.

## Before you start

1. `git pull`, then `gh issue list --state open`. Data-error reports arrive as issues.

## Layout

- `docs/` is the site: vanilla ES modules, libraries from public CDNs with pinned versions, no build step (same pattern as Data Crawler Carl).
- `docs/data/` holds the built database (`herd.duckdb`) and Parquet copies of each table. Do not edit these by hand; rebuild them.
- `pipeline/` builds the data in R. `pipeline/raw/` is downloaded source data and is gitignored.
- `pipeline/carnegie_overrides.csv` is a hand-checked crosswalk for HERD reporting units without a usable IPEDS ID. Add a row, with a note, when a new unit appears.
- `model/` fits the projection model and writes simulation draws (R, run once a year).

## Rebuild the data

```bash
Rscript pipeline/build.R
```

The build fails if any national rollup differs from the totals NCSES publishes. Do not loosen that check to make a build pass; find the cause.

## Rules

- Never change a reported HERD value. Reshaping only.
- Every chart carries a source line. Every projection carries the projection disclaimer (see README.md).
- Keys for the Ask page live in sessionStorage only; a `?key=` parameter is read once and stripped.
- Never use em dashes in site text.

## Local preview

```bash
python3 -m http.server 4173 -d docs
```
