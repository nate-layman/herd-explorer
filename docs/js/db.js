// DuckDB-WASM in the browser, reading the Parquet files in docs/data/.
// Every page shares one database; tables are views over the Parquet files, so
// only the bytes a query needs are downloaded.
import * as duckdb from 'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.32.0/+esm';

const TABLES = [
  'metrics', 'measure_catalog', 'institutions', 'institution_groups',
  'national_published', 'cogr_requirements', 'sources',
];

let ready = null;
let database = null;

async function init() {
  const bundle = await duckdb.selectBundle(duckdb.getJsDelivrBundles());
  // Workers must be same-origin, so wrap the CDN worker in a blob
  const workerUrl = URL.createObjectURL(
    new Blob([`importScripts("${bundle.mainWorker}");`], { type: 'text/javascript' }));
  const db = new duckdb.AsyncDuckDB(new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING), new Worker(workerUrl));
  await db.instantiate(bundle.mainModule, bundle.pthreadWorker);
  URL.revokeObjectURL(workerUrl);
  database = db;

  const base = new URL('data/', document.baseURI).href;
  const conn = await db.connect();
  for (const t of TABLES) {
    await db.registerFileURL(`${t}.parquet`, `${base}${t}.parquet`, duckdb.DuckDBDataProtocol.HTTP, false);
    await conn.query(`CREATE VIEW ${t} AS SELECT * FROM read_parquet('${t}.parquet')`);
  }
  // One row per institution: its most recent name and attributes, plus its sector
  await conn.query(`
    CREATE VIEW institution_latest AS
    SELECT i.* EXCLUDE (year), i.year AS latest_year, g.sector, g.sector_source, g.msi, g.hsi, g.tribal, g.land_grant
    FROM (SELECT * FROM institutions QUALIFY row_number() OVER (PARTITION BY inst_id ORDER BY year DESC) = 1) i
    JOIN institution_groups g USING (inst_id)`);
  return conn;
}

export function connection() {
  ready ??= init();
  return ready;
}

// Run SQL and return plain objects. BigInt values become numbers.
export async function query(sql) {
  const conn = await connection();
  const result = await conn.query(sql);
  return result.toArray().map(row => {
    const o = row.toJSON();
    for (const k in o) if (typeof o[k] === 'bigint') o[k] = Number(o[k]);
    return o;
  });
}

// Quote a string for SQL
export const lit = s => `'${String(s).replaceAll("'", "''")}'`;

// Run SQL and return { column: array } for libraries that take columns (Perspective)
export async function columns(sql) {
  const conn = await connection();
  const table = await conn.query(sql);
  const out = {};
  for (const f of table.schema.fields) {
    const v = table.getChild(f.name).toArray();
    out[f.name] = typeof v[0] === 'bigint' ? Array.from(v, Number) : Array.from(v);
  }
  return out;
}

// Register a Parquet file under docs/data/ as a view the first time it is needed
const registered = new Map();
export async function ensureView(view, path) {
  if (!registered.has(view)) {
    registered.set(view, (async () => {
      const conn = await connection();
      const db = database;
      const url = new URL(`data/${path}`, document.baseURI).href;
      await db.registerFileURL(path, url, duckdb.DuckDBDataProtocol.HTTP, false);
      await conn.query(`CREATE VIEW ${view} AS SELECT * FROM read_parquet('${path}')`);
    })());
  }
  return registered.get(view);
}
