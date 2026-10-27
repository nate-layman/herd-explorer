#!/usr/bin/env bash
# Publish the projection draws and model tables to the Hugging Face dataset the site reads from.
# Run after model/fit.R. Needs the Hugging Face CLI (pip install huggingface_hub) and `hf auth login`.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="n8layman/herd-explorer-projections"
cp model/DATASET_CARD.md model/output/README.md
hf repos create "$REPO" --repo-type dataset --public --exist-ok >/dev/null
hf upload "$REPO" model/output . --repo-type dataset --commit-message "Projections fitted $(date +%Y-%m-%d)"
echo "published https://huggingface.co/datasets/$REPO"
