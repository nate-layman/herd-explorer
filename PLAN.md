# HERD Explorer plan

Decided 2026-10-27 with Nathan Layman.

## Goal

An interactive site for exploring the NCSES Higher Education Research and Development (HERD) Survey over time, any way you want to slice it: one institution, a peer group, a state, public or private, HBCUs, medical schools, or the whole nation. Every chart can show a projection. People can download the data and report errors.

## Constraints

- **Frontend only.** GitHub Pages serves static files from `docs/`. No server at runtime. Queries, charts and projections run in the visitor's browser.
- **No build step for the site**, same as Data Crawler Carl: vanilla ES modules, libraries from public CDNs with pinned versions.
- **Data prep runs offline** (`pipeline/`), once per NCSES release, and writes static files into `docs/data/`.
- **Years: FY 2012 to FY 2024.** One survey design throughout (the post-2010 redesign), stable institution IDs, and short-form files for small institutions every year, so national rollups are complete.
- **License:** Apache 2.0 with NOTICE and CITATION.cff, matching Data Crawler Carl.

## Data

- Source: NCSES public microdata, one standard-form and one short-form file per year: https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development
- Long format: institution, year, question, row, column, value (thousands of dollars, or counts for personnel), plus institution attributes (state, control, HBCU, medical school, highest degree).
- Pipeline output:
  - `docs/data/herd.parquet`: the tidy fact table, for DuckDB-WASM.
  - `docs/data/institutions.parquet`: one row per institution and year with attributes.
  - Download files: full CSV (zipped), XLSX of curated summary tables, and current-view export to CSV or XLSX in the browser.
- **Not in the public files:** NCSES does not release, per institution, the split of institution funds into institutionally financed research, cost sharing, unrecovered indirect costs and recovered indirect costs (HERD data user guide, section 1.1.4). Those appear only as national totals in the published tables, so the site carries them as a separate national series taken from NSF 26-304 Tables 2 and 12, labeled as such.
- **Validation:** national rollups must equal the totals NCSES publishes (HERD FY 2024 data tables, NSF 26-304, Tables 1, 2 and 12). The pipeline fails if any total is off.

## Site

| Page | What it does | Built with |
|---|---|---|
| Trends | National and group trends with nominal, inflation-adjusted, indexed and share views, linked filters | Mosaic (vgplot) over DuckDB-WASM |
| Compare | Pick institutions, states or groups and overlay trends, with projections | Plotly |
| Explore | Drag-and-drop charts on the full table | Graphic Walker |
| Pivot | Pivot grid and charts for power users, with export | Perspective |
| Ask | Questions about the data in plain language; the model writes SQL that runs locally in DuckDB-WASM | Key passthrough copied from Promptulus |
| Every institution | One small chart per institution, sortable and filterable by growth, size, state and projected direction, to spot trends across hundreds of series | trelliscopejs (R, built offline, static output) |
| Data & sources | Provenance, survey notes, downloads, methods and backtest results | |

Every page has a footer linking the GitHub repo and a "Report a data error" issue template. Every chart carries a source line.

**Disclaimer, site-wide.** Every page footer and the Data & sources page carry the disclaimer from README.md: independent project, not an official NCSES or NSF product, not endorsed by NCSES, NSF or the University of Idaho; data, charts and projections provided as is without warranty; not financial, budget, legal or investment advice; check figures against official NCSES tables before relying on them. Downloads include the same text in a README inside the zip and on a sheet in the XLSX. Have University of Idaho General Counsel review the wording before public launch.

## Front end vs. R

The site is a fast JavaScript front end. R runs offline only: mgcv projection fits, the trelliscopejs "Every institution" display, and a DataExplorer data-quality report. In the browser, R loads through webR only when someone asks for a projection on a custom slice. Shinylive was considered and set aside: it loads the R runtime before anything appears.

## Projections

Chosen by backtest (model/fit.R; rolling cutoffs 2018-2021, 1-3 years ahead, CRPS on the log scale). Three candidates:

| Model | CRPS | 80% band covers | 90% band covers |
|---|---|---|---|
| Hierarchical growth (used) | 0.205 | 83% | 90% |
| Naive: own average growth | 0.240 | 66% | 75% |
| Hierarchical GAM on levels (GP sector smooths, AR(1)) | 0.255 | 72% | 80% |

The GAM on levels (first proposal) pulled institutions back toward a trend line; university R&D behaves close to a random walk with drift, so the production model pools growth rates instead and anchors at the last observed value:

```r
bam(dlog ~ sector + s(state, bs = "re") + s(inst, bs = "re") + s(fyear, bs = "re") + s(fyear_x_sector, bs = "re"))
```

- Shared year and year-by-sector shocks are simulated for future years, so group totals carry shared uncertainty.
- Year-to-year noise is a smooth function of institution size (`gam(log|resid| ~ s(lag_y))`, a two-step location-scale model). Without it, bands were far too wide for large institutions and too narrow for small ones.
- Intervals are widened by a factor chosen in the backtest (1.3) so coverage matches nominal in every size group.
- 200 draws per institution and year, FY 2025-2029, nine headline measures, stored as Parquet. The site sums draws within any group before taking percentiles.
- **Disclaimer on every projection.** Any chart showing a projection carries a short note beside it: "Projection: a best guess from past trends, not a forecast. It may not reflect what actually happens. How projections are made." The link goes to the methods page, which explains the model in plain language, shows backtest results, and lists what the model cannot see (policy changes, agency budgets, survey revisions, an institution's own plans).

## Ask (AI questions)

- One key box, routed by prefix, as in Promptulus: `mr2_` to MindRouter through the lakehouse proxy, `sk-ant-` to Claude, other `sk-` to OpenAI, anything else to Gemini.
- A `?key=` URL parameter is read once and stripped from the address bar. Keys live in sessionStorage only.
- The model returns SQL and a JSON chart spec. SQL runs read-only against the local DuckDB-WASM tables; chart specs are validated before rendering. No eval.
- The proxy allowlists origins one at a time. `https://nate-layman.github.io` is already allowed (preflight checked 2026-10-27).

## Phases

1. Scaffold: repo, license, NOTICE, CITATION, README, issue templates, Pages workflow.
2. Pipeline: download, combine, tidy, validate against published totals, write Parquet and downloads.
3. First release: Trends, Compare, Explore, Pivot, Data & sources.
4. Projections: offline fits, backtests, webR refits for custom slices.
5. Ask page.
6. Yearly refresh when NCSES publishes a new year.
