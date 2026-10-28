#!/usr/bin/env bash
# Publish the projection draws and model tables to the Hugging Face dataset the site reads from.
# Run after model/fit.R. Rebuilds the group and institution files from the detail draws and
# checks them first (model/aggregate.R), so derived files can never be published stale.
# Needs R and the Hugging Face CLI (`hf`, from pip install huggingface_hub; if it is not
# installed, uvx runs it). Authenticate with `hf auth login` or an HF_TOKEN environment variable.
# Usage: model/publish.sh [--dry-run]   (--dry-run does everything except the upload)
set -euo pipefail
cd "$(dirname "$0")/.."
DRY_RUN=false; [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
REPO="n8layman/herd-explorer-projections"
if command -v hf >/dev/null; then HF=(hf); else HF=(uvx --from huggingface_hub hf); fi

# The draws must cover the years release.yml promises, or the site would show a stale fit
Rscript -e '
  source("pipeline/release.R"); r <- read_release()
  info <- DBI::dbGetQuery(DBI::dbConnect(duckdb::duckdb()),
    "SELECT max(last_projected_year) AS y FROM read_parquet(\x27model/output/model_info.parquet\x27)")
  if (is.na(info$y) || info$y != r$projection$last_year)
    stop("model/output projects to ", info$y, " but release.yml expects ", r$projection$last_year, "; run Rscript model/fit.R")'

Rscript model/aggregate.R
# The card's {{placeholders}} are filled from release.yml
Rscript -e '
  source("pipeline/release.R"); r <- read_release()
  card <- readLines("model/DATASET_CARD.md")
  vals <- c(first_year = r$first_year, last_year = r$last_year,
            projection_first_year = r$projection$first_year, projection_last_year = r$projection$last_year)
  for (k in names(vals)) card <- gsub(sprintf("{{%s}}", k), vals[[k]], card, fixed = TRUE)
  if (any(grepl("{{", card, fixed = TRUE))) stop("unfilled placeholder in model/DATASET_CARD.md")
  writeLines(card, "model/output/README.md")'
FIT_ID=$(Rscript -e "cat(DBI::dbGetQuery(DBI::dbConnect(duckdb::duckdb()), \"SELECT any_value(fit_id) FROM read_parquet('model/output/model_info.parquet')\")[[1]])")
if $DRY_RUN; then echo "dry run: would publish model/output (fit_id $FIT_ID) to https://huggingface.co/datasets/$REPO"; exit 0; fi
"${HF[@]}" repos create "$REPO" --repo-type dataset --public --exist-ok >/dev/null
# --delete removes remote files that no longer exist locally (an institution that left the survey)
"${HF[@]}" upload "$REPO" model/output . --repo-type dataset --delete "*" \
  --commit-message "Projections fitted $(date +%Y-%m-%d), fit_id $FIT_ID"
echo "published https://huggingface.co/datasets/$REPO"
