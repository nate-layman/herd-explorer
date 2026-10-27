// Projection bands for any group of institutions, from the simulation draws in
// <measure>.parquet files on Hugging Face (see PROJECTIONS). Draws are summed within each group before
// taking percentiles, because percentiles of institutions do not add up to the
// percentile of their total.
import { query, ensureView, lit } from './db.js';

// Projection draws are published to Hugging Face by model/publish.sh
export const PROJECTIONS = 'https://huggingface.co/datasets/n8layman/herd-explorer-projections/resolve/main/';

export const DISCLAIMER_SHORT =
  'Projection: a best guess from past trends, not a forecast. It may not reflect what actually happens.';

let info = null;
export async function projectedMeasures() {
  info ??= (async () => {
    await ensureView('model_info', `${PROJECTIONS}model_info.parquet`);
    return query('SELECT * FROM model_info');
  })();
  return info;
}

export async function hasProjection(measureId) {
  return (await projectedMeasures()).some(m => m.measure_id === measureId && m.status === 'ok');
}

// Turn the projection checkbox on or off for a measure and say why when it is off.
// extraReason covers page-level cases, such as shares of a total.
export async function updateToggle(checkbox, flag, measureId, extraReason = null) {
  const info = (await projectedMeasures()).find(m => m.measure_id === measureId);
  const reason = extraReason ?? (info?.status === 'ok' ? null
    : info?.reason ?? 'No projection has been fit for this measure.');
  checkbox.disabled = !!reason;
  flag.hidden = !reason;
  flag.textContent = reason ? `⚠ Projection unavailable: ${reason}` : '';
  return !reason;
}

// groupSql: a SELECT returning (inst_id, grp) for the institutions to include.
// Returns rows of { grp, year, p05, p10, p50, p90, p95 } in thousands of dollars.
// Institutions in a group that were not modeled (too few years, or not reporting in
// the last year) contribute their last reported value, held flat.
export async function projectionBands(measureId, groupSql) {
  const view = `proj_${measureId}`;
  await ensureView(view, `${PROJECTIONS}${measureId}.parquet`);
  return query(`
    WITH groups AS (${groupSql}),
    last_year AS (SELECT max(year) AS y FROM metrics WHERE measure_id = ${lit(measureId)}),
    modeled AS (SELECT DISTINCT inst_id FROM ${view}),
    flat AS (
      SELECT g.grp, sum(m.value) AS v
      FROM metrics m JOIN groups g USING (inst_id)
      WHERE m.measure_id = ${lit(measureId)} AND m.year = (SELECT y FROM last_year)
        AND m.inst_id NOT IN (SELECT inst_id FROM modeled)
      GROUP BY g.grp),
    totals AS (
      SELECT g.grp, p.year, p.draw, sum(p.value) AS total
      FROM ${view} p JOIN groups g USING (inst_id)
      GROUP BY ALL)
    SELECT t.grp, t.year,
           quantile_cont(t.total + coalesce(f.v, 0), 0.05) AS p05,
           quantile_cont(t.total + coalesce(f.v, 0), 0.10) AS p10,
           quantile_cont(t.total + coalesce(f.v, 0), 0.50) AS p50,
           quantile_cont(t.total + coalesce(f.v, 0), 0.90) AS p90,
           quantile_cont(t.total + coalesce(f.v, 0), 0.95) AS p95
    FROM totals t LEFT JOIN flat f USING (grp)
    GROUP BY ALL ORDER BY t.grp, t.year`);
}

// Plotly traces for one group's band: 90% band, 80% band and the median, joined to
// the last observed point so the projection starts where the data end.
export function bandTraces(bands, last, color, scale, name) {
  const xs = [last.year, ...bands.map(b => b.year)];
  const at = k => [last.value, ...bands.map(b => b[k])].map(scale);
  const fill = (lo, hi, opacity, label) => ([
    { x: xs, y: at(lo), mode: 'lines', line: { width: 0 }, hoverinfo: 'skip', showlegend: false, legendgroup: name },
    { x: xs, y: at(hi), mode: 'lines', line: { width: 0 }, fill: 'tonexty', fillcolor: hexA(color, opacity),
      hoverinfo: 'skip', showlegend: false, legendgroup: name, name: label },
  ]);
  return [
    ...fill('p05', 'p95', 0.12, '90% range'),
    ...fill('p10', 'p90', 0.18, '80% range'),
    { x: xs, y: at('p50'), mode: 'lines', line: { color, width: 2, dash: 'dot' }, name: `${name} (projected)`,
      legendgroup: name, showlegend: false,
      customdata: xs.map((_, i) => i === 0 ? null : [scale(bands[i - 1].p10), scale(bands[i - 1].p90)]),
      hovertemplate: '%{y:.3s} projected<br>80% range %{customdata[0]:.3s} to %{customdata[1]:.3s}<extra>%{fullData.legendgroup}</extra>' },
  ];
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}
