#!/usr/bin/env bash
# Publish the projection draws and model tables to the Hugging Face dataset the site reads from.
# Run after model/fit.R. Rebuilds the group and institution files from the detail draws and
# checks them first (model/aggregate.R), so derived files can never be published stale.
# Needs R, the Hugging Face CLI (pip install huggingface_hub) and `hf auth login`.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="n8layman/herd-explorer-projections"
Rscript model/aggregate.R
cp model/DATASET_CARD.md model/output/README.md
hf repos create "$REPO" --repo-type dataset --public --exist-ok >/dev/null
# --delete removes remote files that no longer exist locally (an institution that left the survey)
hf upload "$REPO" model/output . --repo-type dataset --delete "*" \
  --commit-message "Projections fitted $(date +%Y-%m-%d), fit_id $(Rscript -e "cat(duckdb::dbGetQuery(DBI::dbConnect(duckdb::duckdb()), \"SELECT any_value(fit_id) FROM read_parquet('model/output/model_info.parquet')\")[[1]])")"
echo "published https://huggingface.co/datasets/$REPO"
