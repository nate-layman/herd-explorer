# The projection model (model.html)

## The model in words

University R&D budgets behave much like a random walk with drift: a jump in one year tends to persist, and spending grows at some typical rate with year-to-year surprises. So the model describes growth, the change in log spending from one year to the next, and every projection starts from the institution's last reported value (FY {last_year}).

- **Typical growth by type** (fixed effect): R1, R2, master's institutions and so on each get their own average growth rate.
- **State and institution** (random effects): each may grow faster or slower than its type, with partial pooling, so an institution with a short or noisy history is pulled toward its type and state. In the fitted models these effects come out very small.
- **Shared shocks** (random effects by year, and by year within type): good and bad years hit many institutions at once, such as the 2013 sequestration or the post-2021 jump. New shocks are simulated for each future year, shared by every institution in that simulated future, so group totals have a realistic range.
- **Size-dependent noise**: leftover variation is far larger for small institutions than large ones; its size is a smooth function of institution size.

## Which institutions are modeled

An institution is modeled if it reported a positive amount in at least four years and reported in FY {last_year}. Others are held at their last reported value when a group is projected. Institution type is the 2021 Carnegie Classification; small types (associate's and tribal colleges, system offices, independent research institutes, unclassified units) are pooled as "Other" for modeling.

## The model in symbols

With y = log spending (nominal dollars) and g = y(t) - y(t-1):

- g(i,t) ~ Normal(eta(i,t), sigma(y(i,t-1)))
- eta(i,t) = mu(type) + a(state) + u(institution) + gamma(year) + delta(year, type)
- a, u, gamma, delta are normal random effects; log sigma(y) = f(y), a thin-plate spline with 6 basis functions.

Fit by REML in mgcv, one model per measure:

```r
bam(growth ~ sector
      + s(state, bs = "re")          # state
      + s(inst, bs = "re")           # institution
      + s(year, bs = "re")           # shock shared by every institution in a year
      + s(year_x_sector, bs = "re"), # shock shared within a type in a year
    method = "fREML")
# Noise that depends on size (two-step location-scale model)
gam(log(abs(residual)) ~ s(log(last_value), k = 6))
sigma(size) = exp(fitted + 0.635)  # E[log|z|] = -0.635 for normal z
```

## Simulation

1. Draw 200 sets of coefficients from their estimated distribution (including smoothing-parameter uncertainty).
2. For each future year, draw a new national shock and a new shock per institution type, shared within the draw.
3. Add each institution's own noise, sized to the institution's FY {last_year} value.
4. Accumulate growth from FY {last_year} for {projection_horizon} years.
5. Widen every source of randomness by a factor chosen in backtesting (1.3 at the FY 2024 fit).

Groups are summed draw by draw (with unmodeled institutions held flat), then the 10th to 90th and 5th to 95th percentiles give the bands. Individual institutions' ranges cannot simply be added.

## How it was tested

The model was fit on data through each year from FY {backtest_first_cutoff} to FY {backtest_last_cutoff} in turn and asked to project the next one to three years, which had already happened. Projections were scored with the continuous ranked probability score (CRPS) on the log scale; lower is better.

Results when the model was chosen (FY 2024 data; About the model shows the current fit):

| Model | CRPS | 80% band covers | 90% band covers |
|---|---|---|---|
| Hierarchical growth (used) | 0.205 | 83% | 90% |
| Naive: each institution's own average growth | 0.240 | 66% | 75% |
| Hierarchical GAM on levels (Gaussian process trends by type, AR(1) errors) | 0.255 | 72% | 80% |

The GAM on levels was the first design; it pulled institutions back toward a trend line, which real R&D does not do. Before widening, only about 73 percent of outcomes fell inside the 80 percent range; the 1.3 factor was the candidate whose coverage came closest to 80 and 90 percent in every size group. Without the size-dependent noise, bands were far too wide for large institutions and too narrow for small ones.

The About the model page (model.html) shows the backtest results by institution size and the fitted model summaries.

## Reproduce it

Everything is in the GitHub repository: `Rscript pipeline/build.R` rebuilds the data, `Rscript model/fit.R` refits, tests and simulates, and `model/publish.sh` rebuilds the group and institution files, checks them and publishes to Hugging Face (n8layman/herd-explorer-projections). The model is refit once a year when NCSES releases a new survey year.
