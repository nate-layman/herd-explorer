// Measure picker built from measure_catalog, grouped by category.
import { query } from './db.js';

let catalog = null;

export async function measures() {
  catalog ??= query('SELECT * FROM measure_catalog');
  return catalog;
}

export async function fillMeasureSelect(select, selected = 'source_all_r_d') {
  const rows = await measures();
  const groups = new Map();
  for (const r of rows) {
    if (!groups.has(r.category)) groups.set(r.category, []);
    groups.get(r.category).push(r);
  }
  select.innerHTML = [...groups].map(([cat, items]) =>
    `<optgroup label="${cat}">${items.map(m =>
      `<option value="${m.id}"${m.id === selected ? ' selected' : ''}>${m.label}</option>`).join('')}</optgroup>`).join('');
}

export async function measure(id) {
  return (await measures()).find(m => m.id === id);
}
