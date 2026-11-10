// Explore's Animate tab: bar races, line races, moving scatter plots and maps that play through the survey years.
// Options are deliberately few: a short list of measures, bounded counts, and every query returns at most one row
// per institution, year and measure (about 12,000 rows), so no choice can ask the browser to animate the whole table.
import { query, lit } from './db.js';
import { plotly, PALETTE, OTHER, BASE_LAYOUT, CONFIG, short, unitAxis } from './charts.js';

// Measures offered for animation, in this order
export const MEASURE_IDS = [
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
// Bar races can show 20 or more bars over the years, more than the 8 chart colors, so they add four more
const RACE_PALETTE = [...PALETTE, '#0e8fa3', '#8c5a2b', '#b5b800', '#a03c96'];

export const EXAMPLES = {
  // NSF funding reshuffles its top 15 more than any other measure; computer science does the same among states
  institutions: { type: 'bar', show: 'institutions', measure: 'agency_nsf', n: 15 },
  states: { type: 'bar', show: 'states', measure: 'field_computer_and_information_sciences', n: 15 },
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
  const [{ byId, sectors, states, offered }, Plotly] = await Promise.all([lookups(), plotly()]);
  const { build, note } = builders(chart, byId, M);

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
  $('an-sector').append(opt('', 'All types'), ...sectors.map(s => opt(s, s)));
  $('an-state').append(opt('', 'All states'), ...states.map(s => opt(s, s)));

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

  // ── Draw ───────────────────────────────────────────────────────────────
  let token = 0;
  async function render() {
    const c = readForm();
    const mine = ++token;
    $('an-status').hidden = false;
    $('an-status').textContent = 'Building the animation…';
    let fig;
    try {
      fig = await build(c);
    } catch (e) {
      if (mine === token) $('an-status').textContent = `Could not build this animation: ${e.message}`;
      return;
    }
    if (mine !== token) return;
    await clear(Plotly, chart);
    if (!fig) {
      $('an-status').textContent = 'No data for these choices. Try removing a filter.';
      $('an-note').textContent = '';
      return;
    }
    $('an-status').hidden = true;
    await plot(Plotly, chart, fig);
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
  // A link from Ask (explore.html?type=bar&show=...#animate) opens that animation; otherwise the first example
  const linked = fromParams(new URLSearchParams(location.search));
  const checked = linked && checkAnimation(linked, { byId, sectors, states });
  if (checked && !checked.error) {
    setForm(checked);
    press(null);
  } else {
    setForm(EXAMPLES.institutions);
    press('institutions');
  }
  await render();
}

// ── Shared with the Ask page ────────────────────────────────────────────────

// Measure labels and the allowed filter values, looked up once
let lookupsP = null;
function lookups() {
  lookupsP ??= Promise.all([
    query('SELECT id, category, label, unit FROM measure_catalog'),
    query('SELECT DISTINCT sector FROM institution_latest WHERE sector IS NOT NULL ORDER BY sector'),
    query('SELECT DISTINCT state FROM institution_latest WHERE state IS NOT NULL ORDER BY state'),
  ]).then(([catalog, sectors, states]) => {
    const byId = Object.fromEntries(catalog.map(m => [m.id, m]));
    return { byId, offered: MEASURE_IDS.filter(id => byId[id]), sectors: sectors.map(r => r.sector), states: states.map(r => r.state) };
  });
  return lookupsP;
}

// Check a description of an animation against the same short lists the Animate tab offers. Anything not on a list
// is refused, so a description (from the Ask page's model, or a link) cannot ask for more than the tab can build.
// Returns a complete settings object, or { error }.
export function checkAnimation(spec, { byId, sectors, states }) {
  if (!spec || typeof spec !== 'object') return { error: 'The animation description was not valid.' };
  const type = spec.animation ?? spec.type;
  if (!COUNTS[type]) return { error: `Unsupported animation "${type}". Use bar, line, scatter or map.` };
  const c = { ...DEFAULTS, type, speed: 'normal' };
  const measure = id => MEASURE_IDS.includes(id) && byId[id];
  for (const k of ['measure', 'x', 'y']) {
    if (spec[k] == null) continue;
    if (!measure(spec[k])) return { error: `"${spec[k]}" is not one of the measures animations can use (the Animate tab's Measure list).` };
    c[k] = spec[k];
  }
  if (spec.show != null) {
    if (!SHOW[spec.show]) return { error: `"show" must be one of ${Object.keys(SHOW).join(', ')}.` };
    c.show = spec.show;
  }
  if (spec.sector) {
    if (!sectors.includes(spec.sector)) return { error: `Unknown institution type "${spec.sector}".` };
    c.sector = spec.sector;
  }
  if (spec.state) {
    if (!states.includes(spec.state)) return { error: `Unknown state "${spec.state}". Use a two-letter code.` };
    c.state = spec.state;
  }
  if (spec.speed && SPEED[spec.speed]) c.speed = spec.speed;
  if (spec.log != null) c.log = Boolean(spec.log);
  // A count not offered for this animation snaps to the nearest one that is
  const ns = COUNTS[type].map(([v]) => v);
  const want = Number(spec.n);
  c.n = spec.n == null || Number.isNaN(want) ? ns[Math.min(1, ns.length - 1)]
      : ns.includes(want) ? want
      : type === 'map' && want > 300 ? 0
      : ns.filter(v => v > 0).reduce((a, b) => Math.abs(b - want) < Math.abs(a - want) ? b : a);
  return c;
}

const PARAMS = ['type', 'show', 'measure', 'x', 'y', 'n', 'sector', 'state', 'speed', 'log'];
function fromParams(q) {
  if (!q.has('type')) return null;
  const spec = Object.fromEntries(PARAMS.filter(k => q.has(k)).map(k => [k, q.get(k)]));
  if (spec.log != null) spec.log = spec.log !== '0';
  return spec;
}

// A link that opens these settings on Explore's Animate tab
export function animateLink(c) {
  const q = new URLSearchParams();
  // Only the settings this animation uses
  const groups = c.type === 'bar' || c.type === 'line';
  const used = { type: true, n: !(c.type === 'bar' && c.show in BREAKDOWN), show: groups,
    measure: groups ? !(c.show in BREAKDOWN) : c.type === 'map', x: c.type === 'scatter', y: c.type === 'scatter',
    log: c.type === 'scatter', speed: c.speed !== 'normal', sector: Boolean(c.sector), state: Boolean(c.state) };
  for (const k of PARAMS) if (used[k]) q.set(k, k === 'log' ? (c.log ? '1' : '0') : String(c[k]));
  return `explore.html?${q}#animate`;
}

// Stop a playing animation before removing its chart. Otherwise its remaining frames carry on into the next chart
// drawn there, and a line race picks up a bar race's frames.
async function clear(Plotly, el) {
  const old = el.querySelector('.js-plotly-plot');
  if (old) {
    Plotly.animate(old, [], { mode: 'immediate', frame: { duration: 0, redraw: false }, transition: { duration: 0 } }).catch(() => { });
    // A transition already under way still finishes on the old element, so free it once that is done
    setTimeout(() => Plotly.purge(old), 3000);
  }
  el.replaceChildren();
}

// Each chart gets a new element inside el, so nothing from the last one can reach it
async function plot(Plotly, el, fig) {
  await clear(Plotly, el);
  // On a phone the slider gets its own row
  if (el.clientWidth < 700) fig.layout.margin = { ...fig.layout.margin, b: fig.layout.margin.b + 50 };
  const gd = Object.assign(document.createElement('div'), { style: 'height: 100%' });
  el.append(gd);
  await Plotly.newPlot(gd, fig.data, fig.layout, CONFIG);
  await Plotly.addFrames(gd, fig.frames);
}

// Draw an animation described as data into el. Returns { note, link } or { error }; nothing in spec runs as code,
// and every SQL value it reaches is checked against a list or quoted.
export async function drawAnimation(el, spec, M) {
  const [lk, Plotly] = await Promise.all([lookups(), plotly()]);
  const c = checkAnimation(spec, lk);
  if (c.error) return c;
  const { build, note } = builders(el, lk.byId, M);
  const fig = await build(c);
  if (!fig) return { error: 'No data for these choices.' };
  await plot(Plotly, el, fig);
  return { note: note(c), link: animateLink(c) };
}

// The chart builders, for one chart element
function builders(chart, byId, M) {
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

  // Bar race colors: each bar keeps one color through the years. Bars that are ever next to each other always differ;
  // bars ever within two places differ where the colors allow (a greedy coloring, in order of first appearance).
  function raceColors(ranked) {
    const near1 = new Map(), near2 = new Map();
    const order = [];
    for (const m of ranked.values()) {
      const rows = [...m.values()];
      for (const r of rows) {
        if (!near1.has(r.id)) { near1.set(r.id, new Set()); near2.set(r.id, new Set()); order.push(r.id); }
        for (const o of rows) {
          const d = Math.abs(o.rank - r.rank);
          if (o.id !== r.id && d <= 2) (d === 1 ? near1 : near2).get(r.id).add(o.id);
        }
      }
    }
    const color = new Map();
    order.forEach((id, k) => {
      const used = ids => new Set([...ids].map(o => color.get(o)).filter(Boolean));
      const t1 = used(near1.get(id)), t2 = used(near2.get(id));
      // Start from the next color in turn, so colors spread evenly
      const turn = RACE_PALETTE.map((_, j) => RACE_PALETTE[(k + j) % RACE_PALETTE.length]);
      color.set(id, turn.find(c => !t1.has(c) && !t2.has(c)) ?? turn.find(c => !t1.has(c)) ?? turn[0]);
    });
    return color;
  }

  const yearLabel = y => ({ font: { size: chart.clientWidth < 700 ? 26 : 44, color: '#c8c8c8' }, text: `FY ${y}`, xref: 'paper', yref: 'paper', x: 0.98, y: 0.04, xanchor: 'right',
                            yanchor: 'bottom', showarrow: false });

  // Play button and year slider, the same for every animation
  // smooth: the transition fills the whole frame at an even pace, so motion runs on from one year into the next
  // instead of stopping at each year
  function controls(names, c, redraw, smooth = false) {
    const ms = SPEED[c.speed];
    const narrow = chart.clientWidth < 700;
    const anim = { mode: 'immediate', fromcurrent: true, frame: { duration: ms, redraw },
                   transition: { duration: redraw ? 0 : smooth ? ms : ms * 0.85, easing: smooth ? 'linear' : 'cubic-in-out' } };
    return {
      updatemenus: [{ type: 'buttons', showactive: false, x: 0, y: -0.06, xanchor: 'left', yanchor: 'top', direction: 'left',
        pad: { r: 10, t: 10 },
        buttons: [{ label: '▶ Play', method: 'animate', args: [null, anim] },
                  { label: '❚❚ Pause', method: 'animate', args: [[null], { mode: 'immediate', frame: { duration: 0, redraw }, transition: { duration: 0 } }] }] }],
      // The slider starts a fixed distance right of the buttons, so they never overlap whatever the plot width
      sliders: [{ active: 0, x: 0, len: 1, y: narrow ? -0.13 : -0.06, yanchor: 'top', pad: { t: 10, l: narrow ? 0 : 150 },
        currentvalue: { visible: false },
        steps: names.map(n => ({ label: String(n), method: 'animate',
          args: [[String(n)], { mode: 'immediate', frame: { duration: ms, redraw }, transition: { duration: redraw ? 0 : ms * 0.5 } }] })) }],
    };
  }

  // ── Bar race ───────────────────────────────────────────────────────────
  async function barRace(c) {
    const rows = await groupSeries(c);
    const unit = unitOf(c);
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
    const colors = raceColors(ranked);
    const narrow = chart.clientWidth < 700;
    const nameLen = narrow ? 22 : 42;
    const shown = years.filter(y => ranked.get(y).size);
    if (!shown.length) return null;
    // The scale eases toward each year's largest bar instead of jumping to it: it changes by at most 8% a year,
    // starting to grow early when a big jump is coming, and always leaves room for the largest bar and its label.
    // Bars are drawn as a share of that scale on a fixed axis, so a frame changes only the bars and they move in
    // one smooth motion (Plotly would animate an axis change and a bar change one after the other). The value
    // labels and hover give the reported amounts; the axis has no tick labels, since its units shift with the scale.
    const STEP = 1.08;
    const room = shown.map(y => 1.12 * Math.max(...[...ranked.get(y).values()].map(r => r.value), 1));
    for (let k = room.length - 1; k > 0; k--) room[k - 1] = Math.max(room[k - 1], room[k] / STEP);
    for (let k = 1; k < room.length; k++) room[k] = Math.max(room[k], room[k - 1] / STEP);
    const big = chart.clientWidth < 700 ? 26 : 44;
    const frames = shown.map((y, k) => {
      const m = ranked.get(y);
      const at = id => m.get(id);
      // A bar outside the top n waits just below the last one, so it slides in and out without crossing the controls
      const yv = ids.map(id => at(id)?.rank ?? n + 1);
      const xv = ids.map(id => (at(id)?.value ?? 0) / room[k]);
      return {
        name: String(y),
        data: [
          { ids, x: xv, y: yv, marker: { color: ids.map(id => colors.get(id)) },
            customdata: ids.map(id => [ents.get(id).label, short(at(id)?.value, unit),
              c.show === 'institutions' ? ` (${ents.get(id).grp})` : '']) },
          { ids, x: ids.map(() => 0), y: yv, text: ids.map(id => at(id) ? trunc(ents.get(id).label, nameLen) : ' ') },
          { ids, x: xv, y: yv, text: ids.map(id => at(id) ? ` ${short(at(id).value, unit)}` : ' ') },
          // The year, as a trace so the frame has no layout change
          { x: [0.99], y: [n + 0.3], text: [`FY ${y}`] },
        ],
      };
    });
    const f0 = frames[0];
    const data = [
      { type: 'bar', orientation: 'h', ...f0.data[0], width: 0.8, showlegend: false, hovertemplate: '%{customdata[0]}%{customdata[2]}: %{customdata[1]}<extra></extra>' },
      { type: 'scatter', mode: 'text', ...f0.data[1], showlegend: false, textposition: 'middle left', cliponaxis: false, hoverinfo: 'skip',
        textfont: { size: 12 } },
      { type: 'scatter', mode: 'text', ...f0.data[2], showlegend: false, textposition: 'middle right', cliponaxis: false, hoverinfo: 'skip',
        textfont: { size: 12, color: '#555' } },
      { type: 'scatter', mode: 'text', ...f0.data[3], showlegend: false, textposition: 'top left', hoverinfo: 'skip',
        textfont: { size: big, color: '#c8c8c8' } },
    ];
    const layout = {
      ...BASE_LAYOUT, hovermode: 'closest', showlegend: false,
      // Room on the left for the longest name shown, up to a cap
      margin: { l: Math.min(narrow ? 150 : 290, 24 + 6.6 * Math.max(...ids.map(id => trunc(ents.get(id).label, nameLen).length))),
                r: 70, t: 30, b: 60 },
      xaxis: { range: [0, 1], visible: false, fixedrange: true },
      yaxis: { range: [n + 0.5, 0.5], visible: false, fixedrange: true },
      ...controls(frames.map(f => f.name), c, false, true),
    };
    return { data, layout, frames, redraw: false };
  }

  // ── Line race ──────────────────────────────────────────────────────────
  async function lineRace(c) {
    const rows = await groupSeries(c);
    if (!rows.length) return null;
    const unit = unitOf(c);
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
      line: { color: PALETTE[k], width: 2.5 }, marker: { size: 6, color: PALETTE[k] },
      textposition: 'middle right', textfont: { color: PALETTE[k], size: 12 }, cliponaxis: false,
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

  const build = c => ({ bar: barRace, line: lineRace, scatter, map }[c.type](c));
  return { build, note };
}
