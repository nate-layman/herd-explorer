# HERD Explorer

Explore the NCSES Higher Education Research and Development (HERD) Survey from FY 2012 to FY 2024. Compare institutions, states and groups over time, roll up to national figures, pivot the institution-level data any way you like, and download it.

Runs entirely in your browser. Nothing you do on the site is sent to a server.

**Status:** in development. See [PLAN.md](PLAN.md).

## Where the data come from

All figures come from the public, institution-level microdata files that the National Center for Science and Engineering Statistics (NCSES) publishes for the HERD Survey:

https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development

Each fiscal year has a standard-form file (institutions with $1 million or more in R&D) and a short-form file (smaller institutions). The pipeline in [`pipeline/`](pipeline/) downloads both, combines them and checks the national totals against the tables NCSES publishes. HERD Explorer reshapes the data but does not change any reported value.

## About the projections

Charts can show a projection of the next few years. A projection is a best guess from past trends, not a forecast, and it may not reflect what actually happens. It cannot see policy changes, agency budgets, survey revisions or an institution's own plans.

Projections come from a hierarchical generalized additive model fit with the R package mgcv. The model estimates one shared trend for the group you are looking at, lets each institution have its own level and growth rate, and pulls institutions with short or noisy histories toward the group trend. The shaded band shows the range the model considers plausible. The methods page on the site shows how well the model would have predicted past years.

## Disclaimer

HERD Explorer is an independent project. It is not an official product of NCSES or the U.S. National Science Foundation, and neither NCSES, NSF nor the University of Idaho endorses it or is responsible for its content.

The data, charts and projections are provided "as is," without warranty of any kind, as described in the [LICENSE](LICENSE). They may contain errors introduced by the reshaping. They are not financial, budget, legal or investment advice. Before relying on a figure for a decision, check it against the official NCSES tables. Projections are best guesses from past trends and may not reflect what actually happens.

## Found an error?

[Open an issue](https://github.com/nate-layman/herd-explorer/issues/new/choose). Include the page, the institution or slice, the year, and what you expected to see.

## Local preview

```bash
python3 -m http.server 4173 -d docs
```

Then open http://localhost:4173

## Rebuild the data

```bash
Rscript pipeline/build.R
```

## Built with

- [DuckDB-WASM](https://github.com/duckdb/duckdb-wasm) (MIT): the database in your browser
- [Plotly.js](https://github.com/plotly/plotly.js) (MIT): charts
- [Graphic Walker](https://github.com/Kanaries/graphic-walker) (Apache 2.0) and React (MIT): the Chart builder tab on the Explore page
- [Perspective](https://github.com/perspective-dev/perspective) (Apache 2.0): the Table tab on the Explore page
- [marked](https://github.com/markedjs/marked) (MIT) and [DOMPurify](https://github.com/cure53/DOMPurify) (Apache 2.0 or MPL 2.0): rendering answers on the Ask page
- Google Gen AI SDK and Anthropic SDK (Apache 2.0): loaded only on the Ask page, only for those providers' keys
- Offline, in R: duckdb, readxl, mgcv, scoringRules, writexl

## Ask the data

The Ask page lets you ask questions in plain language. Bring your own key: a University of Idaho MindRouter key (`mr2_...`), or an Anthropic, OpenAI or Google Gemini key. Paste it on the page, or open the page from a link like `ask.html?key=...`; the key is read once, removed from the address bar, and kept only in that browser tab. The model writes SQL that runs read-only in your browser; only your question and the query results go to the provider you chose.

## License

Code: Apache 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Cite with [CITATION.cff](CITATION.cff).

This material is based upon work supported by the U.S. National Science Foundation under award 2427549. HERD Explorer is a project of [AI4RA](https://github.com/AI4RA) at the University of Idaho.
