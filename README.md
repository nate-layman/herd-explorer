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

Added as each library goes in, with its license.

## License

Code: Apache 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Cite with [CITATION.cff](CITATION.cff).

This material is based upon work supported by the U.S. National Science Foundation under award 2427549. HERD Explorer is a project of [AI4RA](https://github.com/AI4RA) at the University of Idaho.
