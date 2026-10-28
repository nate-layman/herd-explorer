# HERD Explorer data and projections. Run from the repository root. See RELEASING.md.
#
#   make data      download NCSES files, build docs/data/, check national totals
#   make model     backtest, fit and simulate projections into model/output/
#   make check     aggregate the draws and run every publish check, without uploading
#   make publish   aggregate, check and upload the projections to Hugging Face
#   make all       data, model and check (everything short of uploading)
#   make release   data, model and publish
#   make next      is the next survey year out yet?
#   make packages  install the R packages the pipeline needs

.PHONY: all release data model check publish next packages

all: data model check

release: data model publish

data:
	Rscript pipeline/build.R

model:
	Rscript model/fit.R

check:
	bash model/publish.sh --dry-run

publish:
	bash model/publish.sh

next:
	Rscript pipeline/check_release.R

# R_REPOS pins a package snapshot on CI; locally it defaults to CRAN
packages:
	Rscript -e 'install.packages(c("DBI", "duckdb", "readxl", "writexl", "mgcv", "scoringRules", "yaml", "jsonlite"), repos = Sys.getenv("R_REPOS", "https://cloud.r-project.org"))'
