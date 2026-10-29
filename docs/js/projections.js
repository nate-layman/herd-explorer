// Projection bands from the simulation draws on Hugging Face (see PROJECTIONS). Draws
// are summed within a group before taking percentiles, because percentiles of
// institutions do not add up to the percentile of their total.
import { query, ensureView, lit } from './db.js';

// Projection draws are published to Hugging Face by model/publish.sh
export const PROJECTIONS = 'https://huggingface.co/datasets/n8layman/herd-explorer-projections/resolve/main/';

export const DISCLAIMER_SHORT =
  'A projection shows where past trends lead if they continue. It does not account for known upcoming changes, such as federal budget or policy shifts, and may not reflect what actually happens.';

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

const BANDS = `
  quantile_cont(total, 0.05) AS p05, quantile_cont(total, 0.10) AS p10, quantile_cont(total, 0.50) AS p50,
  quantile_cont(total, 0.90) AS p90, quantile_cont(total, 0.95) AS p95`;

// Bands for the groups Trends shows. by_group/<measure>.parquet holds each group's draws
// already summed (including unmodeled institutions held at their last value). Groups
// outside `top` are folded into otherLabel by adding their draws draw by draw.
// Returns rows of { grp, year, p05, p10, p50, p90, p95 } in dollars.
export const STALE = 'Projection files are being updated. Try again in a few minutes.';

// Derived files carry the fingerprint of the detail draws they were built from; model_info
// carries the fingerprint of the current fit. A mismatch means a partial update, so no band
// is drawn rather than one that might disagree with the details.
async function assertCurrent(view) {
  const want = (await projectedMeasures())[0]?.fit_id;
  const [{ n, id }] = await query(`SELECT count(DISTINCT fit_id) AS n, any_value(fit_id) AS id FROM ${view}`);
  if (!want || n !== 1 || id !== want) throw new Error(STALE);
}

export async function groupBands(measureId, split, top = null, otherLabel = 'All other') {
  const view = `grp_${measureId}`;
  await ensureView(view, `${PROJECTIONS}by_group/${measureId}.parquet`);
  await assertCurrent(view);
  const grp = top ? `CASE WHEN grp IN (${top.map(lit).join(',')}) THEN grp ELSE ${lit(otherLabel)} END` : 'grp';
  return query(`
    WITH totals AS (
      SELECT ${grp} AS grp, year, draw, sum(value) AS total
      FROM ${view} WHERE split = ${lit(split)} GROUP BY ALL)
    SELECT grp, year, ${BANDS} FROM totals GROUP BY ALL ORDER BY grp, year`);
}

// Bands for individual institutions, from by_institution/inst_id=<id>/data_0.parquet, one
// small file per institution. Institutions the model did not project have no file and
// are left out. Returns rows of { grp: inst_id, year, p05, ..., p95 }.
export async function institutionBands(measureId, instIds) {
  const out = [];
  for (const id of instIds) {
    const view = `inst_${id.replace(/\W/g, '_')}`;
    try {
      await ensureView(view, `${PROJECTIONS}by_institution/inst_id=${encodeURIComponent(id)}/data_0.parquet`);
    } catch {
      continue;  // no projection file for this institution
    }
    await assertCurrent(view);
    out.push(...await query(`
      SELECT ${lit(id)} AS grp, year, ${BANDS}
      FROM (SELECT year, draw, value AS total FROM ${view} WHERE measure_id = ${lit(measureId)})
      GROUP BY year ORDER BY year`));
  }
  return out;
}

// Plotly traces for one group's band: 90% band, 80% band and the median, joined to
// the last observed point so the projection starts where the data end.
// label turns a scaled value into hover text, such as v => short(v, 'dollars').
export function bandTraces(bands, last, color, scale, name, label = v => Math.round(v).toLocaleString()) {
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
      customdata: xs.map((_, i) => i === 0 ? null : [bands[i - 1].p50, bands[i - 1].p10, bands[i - 1].p90].map(v => label(scale(v)))),
      hovertemplate: '%{customdata[0]} projected<br>80% range %{customdata[1]} to %{customdata[2]}<extra>%{fullData.legendgroup}</extra>' },
  ];
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}
