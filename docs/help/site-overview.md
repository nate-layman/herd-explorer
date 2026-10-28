# Site overview

HERD Explorer is a browser-based explorer for the NCSES Higher Education Research and Development (HERD) Survey, FY {first_year} to FY {last_year}. Everything runs in your browser; the database loads into the page and queries run locally.

## Pages

- **Trends** (index.html): national R&D over time, or split by a group such as institution type, state or public/private. Optional projection to FY {projection_last_year}.
- **Compare** (compare.html): pick institutions and see their trends side by side, with the median of each one's institution type for context. Optional projections.
- **Explore** (explore.html): every measure for every institution and year. Two tabs:
  - **Table** (explore.html#table): pivot tables with quick views, build-your-own dropdowns, filters and CSV export. See pivot-tables.md.
  - **Chart builder** (explore.html#chart): drag-and-drop charts with example charts to start from. See chart-builder.md.
- **Ask** (ask.html): ask questions in plain language; an AI model writes SQL that runs in your browser. See ask.md.
- **About the model** (model.html): how the projections are made and tested. See projection-model.md.
- **About HERD** (data.html): what the HERD Survey is (who reports, what counts as R&D, timing, history, caveats), then sources, definitions, how the data were put together, downloads. See data-sources.md.

The old Pivot page (pivot.html) now redirects to Explore's Table tab.

## Reporting a data error

Use "Report a data error" in any page footer, which opens a GitHub issue form at github.com/nate-layman/herd-explorer/issues. Include the page, the institution or slice, the year, and what you expected to see.

## Disclaimer

HERD Explorer is an independent project. It is not an official product of NCSES or the U.S. National Science Foundation, and neither NCSES, NSF nor the University of Idaho endorses it. The data, charts and projections are provided as is, without warranty. They are not financial, budget, legal or investment advice. Check figures against the official NCSES tables before relying on them.

## Who made it

A project of AI4RA (ai4ra.uidaho.edu) at the University of Idaho, funded by the U.S. National Science Foundation GRANTED program, award 2427549. Source code is on GitHub (nate-layman/herd-explorer) under the Apache 2.0 license; cite it with the repository's CITATION.cff.
