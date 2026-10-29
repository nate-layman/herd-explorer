// Shared chart settings and helpers for Plotly.
export const PLOTLY = 'https://cdn.jsdelivr.net/npm/plotly.js-dist-min@4.1.2/plotly.min.js';

// Categorical palette, fixed order (validated reference palette, slots 1-8)
export const PALETTE = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'];
export const OTHER = '#9a9a9a';

let plotlyReady = null;
export function plotly() {
  plotlyReady ??= new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = PLOTLY;
    s.onload = () => resolve(window.Plotly);
    s.onerror = reject;
    document.head.appendChild(s);
  });
  return plotlyReady;
}

export const BASE_LAYOUT = {
  font: { family: '-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif', color: '#191919' },
  paper_bgcolor: '#ffffff',
  plot_bgcolor: '#ffffff',
  margin: { l: 70, r: 30, t: 20, b: 50 },
  hovermode: 'x unified',
  xaxis: { dtick: 2, showgrid: false, linecolor: '#bbb', ticks: 'outside' },
  yaxis: { gridcolor: '#ececec', zeroline: false, automargin: true },
  legend: { orientation: 'h', y: -0.15 },
};

export const CONFIG = { responsive: true, displaylogo: false, modeBarButtonsToRemove: ['lasso2d', 'select2d'] };

// Format a value given its unit: whole dollars or whole counts, with commas
export function fmt(value, unit) {
  if (value == null || Number.isNaN(value)) return '';
  return `${unit === 'dollars' ? '$' : ''}${Math.round(value).toLocaleString()}`;
}

export const unitAxis = unit => ({
  dollars: 'Dollars',
  headcount: 'People',
  fte: 'Full-time equivalents',
}[unit] ?? '');
