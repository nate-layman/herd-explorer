// Explore's Animate tab: bar races, line races, moving scatter plots and maps that play through the survey years.
// Options are deliberately few: a short list of measures, bounded counts, and every query returns at most one row
// per institution, year and measure (about 12,000 rows), so no choice can ask the browser to animate the whole table.
import { query, lit } from './db.js';
import { plotly, PALETTE, OTHER, BASE_LAYOUT, CONFIG, short, unitAxis } from './charts.js';

// Measures offered for animation, in this order
const MEASURE_IDS = [
  'source_all_r_d', 'source_federal_government', 'source_business', 'source_institution_funds',
  'source_state_and_local_government', 'source_nonprofit_organizations',
  'agency_hhs', 'agency_nsf', 'agency_dod', 'agency_doe', 'agency_nasa', 'agency_usda',
  'field_life_sciences', 'field_engineering', 'field_computer_and_information_sciences', 'field_physical_sciences',
  'clinical_trials', 'cost_indirect_costs', 'headcount_total',
];

// What the bars or lines stand for. The last three break one total into parts that do not overlap.
const SHOW = {
  institutions: 'Institutions',
  states: 'States',
  sectors: 'Institution types',
  agencies: 'Federal agencies',
  fields: 'Fields of research',
  sources: 'Sources of funds',
};
const BREAKDOWN = {
  agencies: `c.category = 'Federal agency'`,
  fields: `c.category = 'Field of research'`,
  sources: `c.category = 'Source of funds' AND c.id <> 'source_all_r_d'`,
};

const COUNTS = {
  bar: [[10, 'Top 10'], [15, 'Top 15'], [20, 'Top 20']],
  line: [[5, 'Top 5'], [8, 'Top 8']],
  scatter: [[50, 'Top 50 institutions'], [100, 'Top 100 institutions'], [200, 'Top 200 institutions']],
  map: [[100, 'Top 100 institutions'], [300, 'Top 300 institutions'], [0, 'Every institution']],
};
const SPEED = { slow: 1600, normal: 1000, fast: 550 };

// Institution types keep one color everywhere; the small types share gray
const SECTOR_COLOR = {
  'R1': PALETTE[0], 'R2': PALETTE[1], 'Doctoral/Professional': PALETTE[2], "Master's": PALETTE[3],
  'Baccalaureate': PALETTE[4], 'Special focus: medical': PALETTE[5], 'Special focus: research institution': PALETTE[6],
};
const sectorColor = s => SECTOR_COLOR[s] ?? OTHER;

export const EXAMPLES = {
  institutions: { type: 'bar', show: 'institutions', measure: 'source_all_r_d', n: 15 },
  states: { type: 'bar', show: 'states', measure: 'source_federal_government', n: 15 },
  agencies: { type: 'bar', show: 'agencies', sector: 'R1', n: 10 },
  scatter: { type: 'scatter', x: 'source_federal_government', y: 'source_business', n: 100, log: true },
  map: { type: 'map', measure: 'source_all_r_d', n: 0 },
  stateLines: { type: 'line', show: 'states', measure: 'source_all_r_d', n: 5 },
};

const DEFAULTS = { type: 'bar', show: 'institutions', measure: 'source_all_r_d', x: 'source_federal_government',
                   y: 'source_business', n: 15, sector: '', state: '', speed: 'normal', log: true };

const trunc = (s, k) => s.length > k ? `${s.slice(0, k - 1)}…` : s;

export async function loadAnimate(M) {
  const $ = id => document.getElementById(id);
  const chart = $('an-chart');
  const [catalog, sectors, states, Plotly] = await Promise.all([
    query('SELECT id, category, label, unit FROM measure_catalog'),
    query('SELECT DISTINCT sector FROM institution_latest WHERE sector IS NOT NULL ORDER BY sector'),
    query('SELECT DISTINCT state FROM institution_latest WHERE state IS NOT NULL ORDER BY state'),
    plotly(),
  ]);
  const byId = Object.fromEntries(catalog.map(m => [m.id, m]));
  const offered = MEASURE_IDS.filter(id => byId[id]);

  // ── Controls ───────────────────────────────────────────────────────────
  const opt = (value, text) => Object.assign(document.createElement('option'), { value, textContent: text });
  for (const id of ['an-measure', 'an-x', 'an-y']) {
    const groups = new Map();
    for (const mid of offered) {
      const m = byId[mid];
      if (!groups.has(m.category)) groups.set(m.category, Object.assign(document.createElement('optgroup'), { label: m.category }));
      groups.get(m.category).append(opt(mid, m.label));
    }
    $(id).append(...groups.values());
  }
  $('an-show').append(...Object.entries(SHOW).map(([k, v]) => opt(k, v)));
  $('an-sector').append(opt('', 'All types'), ...sectors.map(s => opt(s.sector, s.sector)));
  $('an-state').append(opt('', 'All states'), ...states.map(s => opt(s.state, s.state)));

  function setForm(cfg) {
    const c = { ...DEFAULTS, ...cfg };
    $('an-type').value = c.type;
    $('an-n').replaceChildren(...COUNTS[c.type].map(([v, t]) => opt(v, t)));
    for (const k of ['show', 'measure', 'x', 'y', 'n', 'sector', 'state', 'speed']) $(`an-${k}`).value = String(c[k]);
    if (!$('an-n').value) $('an-n').selectedIndex = 0;
    $('an-log').checked = c.log;
    showFields();
  }
  function readForm() {
    return { type: $('an-type').value, show: $('an-show').value, measure: $('an-measure').value, x: $('an-x').value,
             y: $('an-y').value, n: Number($('an-n').value), sector: $('an-sector').value, state: $('an-state').value,
             speed: $('an-speed').value, log: $('an-log').checked };
  }
  // Each control appears only for the animations it applies to
  function showFields() {
    const c = readForm();
    const groups = c.type === 'bar' || c.type === 'line';
    for (const el of document.querySelectorAll('#an-controls [data-for]')) {
      el.hidden = !el.dataset.for.split(' ').includes(c.type);
    }
    // A breakdown measures its own parts, so the measure does not apply; grouping by a field makes its filter moot
    $('an-measure').closest('label').hidden = groups && c.show in BREAKDOWN || !['bar', 'line', 'map'].includes(c.type);
    $('an-sector').closest('label').hidden = groups && c.show === 'sectors';
    $('an-state').closest('label').hidden = groups && c.show === 'states';
    // A breakdown has ten parts or fewer, so a bar race shows them all
    $('an-n').closest('label').hidden = c.type === 'bar' && c.show in BREAKDOWN;
  }

  // ── Data ───────────────────────────────────────────────────────────────
  function filters(c) {
    const w = [];
    if (c.sector && !(c.type !== 'scatter' && c.type !== 'map' && c.show === 'sectors')) w.push(`i.sector = ${lit(c.sector)}`);
    if (c.state && !(c.type !== 'scatter' && c.type !== 'map' && c.show === 'states')) w.push(`i.state = ${lit(c.state)}`);
    return w.map(s => ` AND ${s}`).join('');
  }

  // One value per group and year: {year, id, label, grp, value}
  async function groupSeries(c) {
    const f = filters(c);
    if (c.show in BREAKDOWN) {
      return query(`
        SELECT m.year, c.id, c.label, c.label AS grp, sum(m.value) AS value
        FROM metrics m JOIN measure_catalog c ON c.id = m.measure_id JOIN institution_latest i USING (inst_id)
        WHERE ${BREAKDOWN[c.show]}${f} GROUP BY ALL`);
    }
    const key = { institutions: 'm.inst_id', states: 'i.state', sectors: 'i.sector' }[c.show];
    const label = { institutions: 'any_value(i.name)', states: 'i.state', sectors: 'i.sector' }[c.show];
    const grp = { institutions: 'any_value(i.sector)', states: 'i.state', sectors: 'i.sector' }[c.show];
    return query(`
      SELECT m.year, ${key} AS id, ${label} AS label, ${grp} AS grp, sum(m.value) AS value
      FROM metrics m JOIN institution_latest i USING (inst_id)
      WHERE m.measure_id = ${lit(c.measure)} AND m.value > 0${f} GROUP BY m.year, ${key}`);
  }

  const years = [];
  for (let y = M.first_year; y <= M.last_year; y++) years.push(y);
  const unitOf = c => c.show in BREAKDOWN && (c.type === 'bar' || c.type === 'line') ? 'dollars' : byId[c.measure].unit;
  const measureName = id => `${byId[id].category}: ${byId[id].label}`;

  // Colors: institutions and types by institution type; anything else by order of size
  function colorer(c, rows) {
    if (c.show === 'institutions' || c.show === 'sectors') return r => sectorColor(r.grp);
    const order = [...new Set([...rows].sort((a, b) => b.value - a.value).map(r => r.id))];
    return r => PALETTE[order.indexOf(r.id) % PALETTE.length];
  }

  const sectorLegend = grps => [...new Set(grps)].sort((a, b) => (SECTOR_COLOR[a] ? 0 : 1) - (SECTOR_COLOR[b] ? 0 : 1) || a.localeCompare(b))
    .map(g => ({ type: 'scatter', mode: 'markers', x: [null], y: [null], name: g, hoverinfo: 'skip',
                 marker: { color: sectorColor(g), size: 10, symbol: 'square' } }));

  const yearLabel = y => ({ font: { size: chart.clientWidth < 700 ? 26 : 44, color: '#c8c8c8' }, text: `FY ${y}`, xref: 'paper', yref: 'paper', x: 0.98, y: 0.04, xanchor: 'right',
                            yanchor: 'bottom', showarrow: false });

  // Play button and year slider, the same for every animation
  function controls(names, c, redraw) {
    const ms = SPEED[c.speed];
    const narrow = chart.clientWidth < 700;
    const anim = { mode: 'immediate', fromcurrent: true, frame: { duration: ms, redraw },
                   transition: { duration: redraw ? 0 : ms * 0.85, easing: 'cubic-in-out' } };
    return {
      updatemenus: [{ type: 'buttons', showactive: false, x: 0, y: -0.06, xanchor: 'left', yanchor: 'top', direction: 'left',
        pad: { r: 10, t: 10 },
        buttons: [{ label: '▶ Play', method: 'animate', args: [null, anim] },
                  { label: '❚❚ Pause', method: 'animate', args: [[null], { mode: 'immediate', frame: { duration: 0, redraw }, transition: { duration: 0 } }] }] }],
      sliders: [{ active: 0, x: narrow ? 0 : 0.17, len: narrow ? 1 : 0.83, y: narrow ? -0.13 : -0.06, yanchor: 'top', pad: { t: 10 },
        currentvalue: { visible: false },
        steps: names.map(n => ({ label: String(n), method: 'animate',
          args: [[String(n)], { mode: 'immediate', frame: { duration: ms, redraw }, transition: { duration: redraw ? 0 : ms * 0.5 } }] })) }],
    };
  }

  // ── Bar race ───────────────────────────────────────────────────────────
  async function barRace(c) {
    const rows = await groupSeries(c);
    const unit = unitOf(c);
    const color = colorer(c, rows);
    const n = c.show in BREAKDOWN ? new Set(rows.map(r => r.id)).size : c.n;
    // Rank within each year; anything that is ever in the top n stays in every frame so it can slide in and out
    const ranked = new Map();
    for (const y of years) {
      const top = rows.filter(r => r.year === y).sort((a, b) => b.value - a.value).slice(0, n);
      ranked.set(y, new Map(top.map((r, k) => [r.id, { ...r, rank: k + 1 }])));
    }
    const ents = new Map();
    for (const m of ranked.values()) for (const r of m.values()) if (!ents.has(r.id)) ents.set(r.id, r);
    const ids = [...ents.keys()];
    const narrow = chart.clientWidth < 700;
    const nameLen = narrow ? 22 : 42;
    const frames = years.filter(y => ranked.get(y).size).map(y => {
      const m = ranked.get(y);
      const at = id => m.get(id);
      const yv = ids.map(id => at(id)?.rank ?? n + 2);
      const xv = ids.map(id => at(id)?.value ?? 0);
      const max = Math.max(...xv, 1);
      return {
        name: String(y),
        data: [
          { ids, x: xv, y: yv, marker: { color: ids.map(id => color(ents.get(id))) },
            customdata: ids.map(id => [ents.get(id).label, short(at(id)?.value, unit)]) },
          { ids, x: ids.map(() => 0), y: yv, text: ids.map(id => at(id) ? trunc(ents.get(id).label, nameLen) : ' ') },
          { ids, x: xv, y: yv, text: ids.map(id => at(id) ? ` ${short(at(id).value, unit)}` : ' ') },
        ],
        layout: { xaxis: { range: [0, max * 1.12] }, annotations: [yearLabel(y)] },
      };
    });
    if (!frames.length) return null;
    const f0 = frames[0];
    const data = [
      { type: 'bar', orientation: 'h', ...f0.data[0], width: 0.8, showlegend: false, hovertemplate: '%{customdata[0]}: %{customdata[1]}<extra></extra>' },
      { type: 'scatter', mode: 'text', ...f0.data[1], showlegend: false, textposition: 'middle left', cliponaxis: false, hoverinfo: 'skip',
        textfont: { size: 12 } },
      { type: 'scatter', mode: 'text', ...f0.data[2], showlegend: false, textposition: 'middle right', cliponaxis: false, hoverinfo: 'skip',
        textfont: { size: 12, color: '#555' } },
      // Legend only: bars of institutions and types are colored by institution type
      ...(c.show === 'institutions' || c.show === 'sectors' ? sectorLegend([...ents.values()].map(r => r.grp)) : []),
    ];
    const layout = {
      ...BASE_LAYOUT, hovermode: 'closest', showlegend: c.show === 'institutions',
      legend: { orientation: 'h', y: 1.01, yanchor: 'bottom', x: 0 },
      margin: { l: narrow ? 150 : 290, r: 70, t: 30, b: 90 },
      xaxis: { ...f0.layout.xaxis, gridcolor: '#ececec', zeroline: false, exponentformat: 'B',
               tickprefix: unit === 'dollars' ? '$' : '', ticksuffix: unit === 'dollars' ? '' : ` ${unitAxis(unit).toLowerCase()}` },
      yaxis: { range: [n + 0.5, 0.5], visible: false, fixedrange: true },
      annotations: f0.layout.annotations,
      ...controls(frames.map(f => f.name), c, false),
    };
    return { data, layout, frames, redraw: false };
  }

  // ── Line race ──────────────────────────────────────────────────────────
  async function lineRace(c) {
    const rows = await groupSeries(c);
    if (!rows.length) return null;
    const unit = unitOf(c);
    const color = colorer(c, rows);
    // The groups largest in the latest year, drawn year by year
    const lastYear = Math.max(...rows.map(r => r.year));
    const keep = rows.filter(r => r.year === lastYear).sort((a, b) => b.value - a.value).slice(0, c.n).map(r => r.id);
    const series = keep.map(id => rows.filter(r => r.id === id).sort((a, b) => a.year - b.year));
    const max = Math.max(...series.flat().map(r => r.value));
    const narrow = chart.clientWidth < 700;
    const frames = years.map(y => ({
      name: String(y),
      data: series.map(s => {
        const pts = s.filter(r => r.year <= y);
        return { x: pts.map(r => r.year), y: pts.map(r => r.value),
                 text: pts.map((r, k) => k === pts.length - 1 ? ` ${trunc(r.label, narrow ? 14 : 30)}` : ''),
                 customdata: pts.map(r => short(r.value, unit)) };
      }),
      layout: { annotations: [{ ...yearLabel(y), x: 0.02, xanchor: 'left', y: 0.96, yanchor: 'top' }] },
    }));
    const data = series.map((s, k) => ({
      type: 'scatter', mode: 'lines+markers+text', name: s[0].label, ...frames[0].data[k],
      line: { color: color(s[0]), width: 2.5 }, marker: { size: 6, color: color(s[0]) },
      textposition: 'middle right', textfont: { color: color(s[0]), size: 12 }, cliponaxis: false,
      hovertemplate: `${s[0].label}<br>FY %{x}: %{customdata}<extra></extra>`,
    }));
    const layout = {
      ...BASE_LAYOUT, hovermode: 'closest', showlegend: false,
      margin: { l: 70, r: narrow ? 110 : 230, t: 20, b: 90 },
      xaxis: { ...BASE_LAYOUT.xaxis, range: [M.first_year - 0.4, M.last_year + 0.4] },
      yaxis: { ...BASE_LAYOUT.yaxis, range: [0, max * 1.08], tickprefix: unit === 'dollars' ? '$' : '', title: { text: unitAxis(unit) } },
      annotations: frames[0].layout.annotations,
      ...controls(frames.map(f => f.name), c, true),
    };
    return { data, layout, frames, redraw: true };
  }

  // ── Moving scatter ─────────────────────────────────────────────────────
  async function scatter(c) {
    const f = filters(c);
    const rows = await query(`
      WITH top AS (
        SELECT m.inst_id FROM metrics m JOIN institution_latest i USING (inst_id)
        WHERE m.measure_id = 'source_all_r_d' AND m.year = ${M.last_year}${f}
        ORDER BY m.value DESC LIMIT ${Number(c.n)})
      SELECT m.year, m.inst_id, any_value(i.name) AS name, any_value(i.sector) AS sector,
             sum(m.value) FILTER (WHERE m.measure_id = ${lit(c.x)}) AS x,
             sum(m.value) FILTER (WHERE m.measure_id = ${lit(c.y)}) AS y,
             sum(m.value) FILTER (WHERE m.measure_id = 'source_all_r_d') AS s
      FROM metrics m JOIN institution_latest i USING (inst_id)
      WHERE m.inst_id IN (SELECT inst_id FROM top) AND m.measure_id IN (${lit(c.x)}, ${lit(c.y)}, 'source_all_r_d')
      GROUP BY m.year, m.inst_id`);
    // Log axes cannot place zero, so those points sit out the year they are zero
    const ok = r => r.x != null && r.y != null && (!c.log || (r.x > 0 && r.y > 0));
    const pts = rows.filter(ok);
    if (!pts.length) return null;
    const ux = byId[c.x].unit, uy = byId[c.y].unit;
    const groups = [...new Set(pts.map(r => r.sector))].sort((a, b) =>
      (SECTOR_COLOR[a] ? 0 : 1) - (SECTOR_COLOR[b] ? 0 : 1) || a.localeCompare(b));
    const smax = Math.max(...pts.map(r => r.s ?? 0), 1);
    const range = (vals) => {
      const lo = Math.min(...vals), hi = Math.max(...vals);
      return c.log ? [Math.log10(lo) - 0.15, Math.log10(hi) + 0.15] : [0, hi * 1.08];
    };
    const frames = years.map(y => ({
      name: String(y),
      data: groups.map(g => {
        const p = pts.filter(r => r.year === y && r.sector === g);
        return { ids: p.map(r => r.inst_id), x: p.map(r => r.x), y: p.map(r => r.y), marker: { size: p.map(r => r.s ?? 0) },
                 customdata: p.map(r => [r.name, short(r.x, ux), short(r.y, uy), short(r.s, 'dollars')]) };
      }),
      layout: { annotations: [yearLabel(y)] },
    }));
    const data = groups.map((g, k) => ({
      type: 'scatter', mode: 'markers', name: g, ...frames[0].data[k],
      marker: { ...frames[0].data[k].marker, color: sectorColor(g), sizemode: 'area', sizeref: 2 * smax / 44 ** 2, sizemin: 3,
                opacity: 0.75, line: { color: '#fff', width: 0.5 } },
      hovertemplate: `%{customdata[0]}<br>${byId[c.x].label}: %{customdata[1]}<br>${byId[c.y].label}: %{customdata[2]}` +
                     `<br>All R&D: %{customdata[3]}<extra>${g}</extra>`,
    }));
    const axis = (id, vals) => ({ type: c.log ? 'log' : 'linear', range: range(vals), ...(c.log ? { dtick: 1 } : {}), gridcolor: '#ececec', zeroline: false,
      exponentformat: 'B', tickprefix: byId[id].unit === 'dollars' ? '$' : '', title: { text: measureName(id) } });
    const layout = {
      ...BASE_LAYOUT, hovermode: 'closest', margin: { l: 80, r: 30, t: 20, b: 130 },
      xaxis: axis(c.x, pts.map(r => r.x)), yaxis: axis(c.y, pts.map(r => r.y)),
      legend: { orientation: 'h', y: 1.02, yanchor: 'bottom', x: 0 },
      annotations: frames[0].layout.annotations,
      ...controls(frames.map(f => f.name), c, false),
    };
    // Room for the axis title above the play controls
    layout.updatemenus[0].y -= 0.08;
    layout.sliders[0].y -= 0.08;
    return { data, layout, frames, redraw: false };
  }

  // ── Map ────────────────────────────────────────────────────────────────
  async function map(c) {
    const f = filters(c);
    const limit = c.n ? `
      AND m.inst_id IN (SELECT m.inst_id FROM metrics m JOIN institution_latest i USING (inst_id)
        WHERE m.measure_id = ${lit(c.measure)} AND m.year = ${M.last_year}${f} ORDER BY m.value DESC LIMIT ${Number(c.n)})` : '';
    const rows = await query(`
      SELECT m.year, m.inst_id, i.name, i.sector, i.latitude, i.longitude, m.value
      FROM metrics m JOIN institution_latest i USING (inst_id)
      WHERE m.measure_id = ${lit(c.measure)} AND m.value > 0 AND i.latitude IS NOT NULL${f}${limit}`);
    if (!rows.length) return null;
    const unit = byId[c.measure].unit;
    const groups = [...new Set(rows.map(r => r.sector))].sort((a, b) =>
      (SECTOR_COLOR[a] ? 0 : 1) - (SECTOR_COLOR[b] ? 0 : 1) || a.localeCompare(b));
    const vmax = Math.max(...rows.map(r => r.value));
    const frames = years.map(y => ({
      name: String(y),
      data: groups.map(g => {
        const p = rows.filter(r => r.year === y && r.sector === g);
        return { ids: p.map(r => r.inst_id), lat: p.map(r => r.latitude), lon: p.map(r => r.longitude),
                 marker: { size: p.map(r => r.value) }, customdata: p.map(r => [r.name, short(r.value, unit)]) };
      }),
      layout: { annotations: [yearLabel(y)] },
    }));
    const data = groups.map((g, k) => ({
      type: 'scattergeo', mode: 'markers', name: g, ...frames[0].data[k],
      marker: { ...frames[0].data[k].marker, color: sectorColor(g), sizemode: 'area', sizeref: 2 * vmax / 40 ** 2, sizemin: 2,
                opacity: 0.7, line: { color: '#fff', width: 0.5 } },
      hovertemplate: `%{customdata[0]}: %{customdata[1]}<extra>${g}</extra>`,
    }));
    const layout = {
      ...BASE_LAYOUT, hovermode: 'closest', margin: { l: 10, r: 10, t: 20, b: 90 },
      geo: { scope: 'usa', projection: { type: 'albers usa' }, showland: true, landcolor: '#f3f3f1',
             subunitcolor: '#d6d6d6', countrycolor: '#d6d6d6', bgcolor: 'rgba(0,0,0,0)' },
      legend: { orientation: 'h', y: 1.02, yanchor: 'bottom', x: 0 },
      annotations: frames[0].layout.annotations,
      ...controls(frames.map(f => f.name), c, true),
    };
    return { data, layout, frames, redraw: true };
  }

  // ── Source line ────────────────────────────────────────────────────────
  function note(c) {
    const span = `FY ${M.first_year}-${M.last_year}`;
    const parts = [];
    const where = [c.sector && (c.type === 'scatter' || c.type === 'map' || c.show !== 'sectors') ? c.sector : '',
                   c.state && (c.type === 'scatter' || c.type === 'map' || c.show !== 'states') ? c.state : ''].filter(Boolean);
    const within = where.length ? ` Only ${where.join(', ')} institutions.` : '';
    if (c.type === 'bar' || c.type === 'line') {
      const what = c.show in BREAKDOWN ? `${SHOW[c.show]}, summed over institutions` : `${measureName(c.measure)}, by ${SHOW[c.show].toLowerCase()}`;
      parts.push(`${what}.${within}`);
      if (c.type === 'bar') parts.push('Each frame ranks one fiscal year.');
      else parts.push(`Lines are the ${c.n} largest in FY ${M.last_year}.`);
    } else if (c.type === 'scatter') {
      parts.push(`${c.n} institutions with the most All R&D in FY ${M.last_year}.${within} Bubble size is All R&D.` +
                 (c.log ? ' Log scales; an institution with zero on either measure sits out that year.' : ''));
    } else {
      parts.push(`${measureName(c.measure)}. Dot size is the amount.${within} Alaska and Hawaii are inset; Puerto Rico and the other territories are not shown.`);
    }
    parts.push('Motion between years is drawn by the animation; only the year marks are reported values.');
    let src = `Source: NCSES HERD Survey public microdata, ${span}, nominal dollars. Institution type from the 2021 Carnegie Classification.`;
    if (c.type === 'map') src += ' Locations: IPEDS directory files (NCES), not HERD data.';
    return `${parts.join(' ')} ${src}`;
  }

  // ── Draw ───────────────────────────────────────────────────────────────
  let token = 0;
  async function render() {
    const c = readForm();
    const mine = ++token;
    $('an-status').hidden = false;
    $('an-status').textContent = 'Building the animation…';
    let fig;
    try {
      fig = await { bar: barRace, line: lineRace, scatter, map }[c.type](c);
    } catch (e) {
      if (mine === token) $('an-status').textContent = `Could not build this animation: ${e.message}`;
      return;
    }
    if (mine !== token) return;
    Plotly.purge(chart);
    chart.innerHTML = '';
    if (!fig) {
      $('an-status').textContent = 'No data for these choices. Try removing a filter.';
      $('an-note').textContent = '';
      return;
    }
    $('an-status').hidden = true;
    // On a phone the slider gets its own row
    if (chart.clientWidth < 700) fig.layout.margin = { ...fig.layout.margin, b: fig.layout.margin.b + 50 };
    await Plotly.newPlot(chart, fig.data, fig.layout, CONFIG);
    await Plotly.addFrames(chart, fig.frames);
    $('an-note').textContent = note(c);
  }

  // ── Wiring ─────────────────────────────────────────────────────────────
  const buttons = $('an-examples');
  const press = name => buttons.querySelectorAll('[data-ex]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.ex === name)));
  buttons.addEventListener('click', e => {
    const ex = e.target.closest('[data-ex]')?.dataset.ex;
    if (!ex) return;
    setForm(EXAMPLES[ex]);
    press(ex);
    render();
  });
  $('an-controls').addEventListener('change', e => {
    if (e.target.id === 'an-type') {
      const c = readForm();
      setForm({ ...c, n: COUNTS[c.type].some(([v]) => v === c.n) ? c.n : COUNTS[c.type][Math.min(1, COUNTS[c.type].length - 1)][0] });
    }
    showFields();
    press(null);
    render();
  });
  setForm(EXAMPLES.institutions);
  press('institutions');
  await render();
}
