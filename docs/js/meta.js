// Years and labels for site text, from docs/data/meta.json (written by pipeline/build.R
// from pipeline/release.yml), so a new survey year needs no edits to the pages.
export const meta = fetch(new URL('../data/meta.json', import.meta.url)).then(r => r.json());

// Fill placeholders in the page. The text already in each element is the fallback.
//   <span data-meta="last_year">2024</span>                       one value
//   <a data-meta-href="tables_page">                               a link address
//   <option data-meta-text="Index (FY {first_year} = 100)">...</option>   a template, for elements that cannot hold a span
export async function fillMeta(root = document) {
  let m;
  try { m = await meta; } catch { return; }
  root.querySelectorAll('[data-meta]').forEach(el => { if (m[el.dataset.meta] != null) el.textContent = m[el.dataset.meta]; });
  root.querySelectorAll('[data-meta-href]').forEach(el => { if (m[el.dataset.metaHref]) el.href = m[el.dataset.metaHref]; });
  root.querySelectorAll('[data-meta-text]').forEach(el => { el.textContent = fillTemplate(el.dataset.metaText, m); });
}

// "FY {last_year}" -> "FY 2024"; unknown names are left as they are
export const fillTemplate = (text, m) => text.replace(/\{(\w+)\}/g, (all, k) => m[k] ?? all);
