# CLAUDE.md, HERD Explorer

## Project

Browser-based explorer for the NCSES HERD Survey, FY 2012 to FY 2024. Static site on GitHub Pages from `docs/`. See PLAN.md for the design and the decisions behind it.

## Before you start

1. `git pull`, then `gh issue list --state open`. Data-error reports arrive as issues.

## Layout

- `docs/` is the site: vanilla ES modules, libraries from public CDNs with pinned versions, no build step (same pattern as Data Crawler Carl).
- `docs/help/` holds the help documents the Ask page's model reads on request, with `contents.md` as their table of contents (the only part sent up front). When you change what a page does, update its help document; when you add a document, add a line to `contents.md`.
- `docs/data/` holds the built database (`herd.duckdb`) and Parquet copies of each table. Do not edit these by hand; rebuild them.
- `pipeline/` builds the data in R. `pipeline/raw/` is downloaded source data and is gitignored.
- `pipeline/carnegie_overrides.csv` is a hand-checked crosswalk for HERD reporting units without a usable IPEDS ID. Add a row, with a note, when a new unit appears.
- `pipeline/location_overrides.csv` does the same for latitude and longitude (from the IPEDS directory file otherwise). The build warns when an institution has no location.
- `model/` fits the projection model and writes simulation draws (R, run once a year).

## Rebuild the data

```bash
make all        # build.R, fit.R, and publish.sh --dry-run
```

Years, the NCSES tables publication and the projection horizon live in `pipeline/release.yml`; nothing else should hardcode them. Site text reads years from `docs/data/meta.json` (written by the build) through `docs/js/meta.js`, and help docs use `{last_year}`-style placeholders. A new survey year is a `release.yml` edit plus the Refresh data workflow; see RELEASING.md.

The build fails if any national rollup differs from the totals NCSES publishes. Do not loosen that check to make a build pass; find the cause.

## Rules

- Never change a reported HERD value. Reshaping only, plus one unit conversion: NCSES reports dollars in thousands, and `pipeline/build.R` multiplies them by 1,000 as it reads them, so everything downstream is whole dollars.
- Every chart carries a source line. Every projection carries the projection disclaimer (see README.md).
- Keys for the Ask page live in sessionStorage only; a `?key=` parameter is read once and stripped.
- Never use em dashes in site text.

## Local preview

```bash
python3 -m http.server 4173 -d docs
```
