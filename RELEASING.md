# Releasing a new HERD survey year

NCSES releases a new year of HERD data each year, usually in late fall. Updating the site takes one config edit and two workflow runs. No code changes are needed.

A monthly GitHub Action (`check-release.yml`) checks whether the next year's microdata is out and opens an issue when it is. You can check by hand with `make next`.

## 1. Edit `pipeline/release.yml`

- `last_year`: the new survey year.
- `tables.publication`: the NCSES publication with that year's data tables, from its address `https://ncses.nsf.gov/pubs/<publication>` (for FY 2024 this was `nsf26304`). Find it from the [HERD survey page](https://ncses.nsf.gov/surveys/higher-education-research-development). The build checks every national total against Tables 2 and 12 of that publication.
- Optional: if COGR has updated its [Figure 1](https://www.cogr.edu/changes-federal-research-requirements-1991), type the new data labels into `pipeline/cogr_requirements.csv` and set `cogr.updated`. If you skip this, the build warns and the workload chart on Trends ends a year early.

Commit the change to `main`.

## 2. Run the Refresh data workflow

Actions tab, **Refresh data**, **Run workflow**. It:

1. downloads the NCSES microdata for every year, the data tables and the Carnegie file,
2. builds `docs/data/`, and stops if any national total differs from what NCSES publishes,
3. backtests, fits and simulates the projections,
4. runs every publish check without uploading,
5. opens a pull request named **Data refresh** with the new `docs/data/`.

## 3. Review and merge the pull request

The pull request lists the years and the projection model the backtest chose. Open the site preview locally if you like (`python3 -m http.server 4173 -d docs`). Merging updates the site, and `publish.yml` then refits the projections (seeded, so identical to the reviewed run) and uploads them to Hugging Face.

Site text, chart labels, the Ask page and its help documents take their years from `docs/data/meta.json`, which the build writes from `release.yml`.

## If the build stops

- **Validation failed**: a national total in the microdata differs from the NCSES table. Do not loosen the check; find the cause (a new form, a changed question number, a table layout change). The message lists every mismatch.
- **Expected one Table N workbook**: NCSES renumbered or renamed its tables. Check the table numbers in `release.yml` against the publication.
- **Download failed**: NCSES may have changed its file addresses. The microdata address pattern is in `pipeline/build.R` (`microdata_url`).
- **A new HERD reporting unit without an IPEDS ID**: add a row to `pipeline/carnegie_overrides.csv` with a note.

## Running it on your own computer

```bash
make packages   # once: install the R packages
make all        # download, build, check, fit, and run the publish checks (no upload)
make publish    # upload the projections (needs `hf auth login` or HF_TOKEN)
```

`make all` takes a few minutes; the model fit is about two minutes and 3 GB of memory.

## One-time setup for the workflows

- Repository secret `HF_TOKEN`: a Hugging Face token with write access to `n8layman/herd-explorer-projections`.
- Settings, Actions, General: allow GitHub Actions to create pull requests.
