import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const I18N_DIR = join(__dirname, '..', 'public', 'i18n');
const API_ERROR_MAPPER = join(
  __dirname,
  '..', '..', '..',
  'api', 'Izvor.Api', 'Errors', 'ApiErrorMapper.cs'
);

function flatten(obj, prefix = '', out = new Set()) {
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix === '' ? k : `${prefix}.${k}`;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      flatten(v, path, out);
    } else {
      out.add(path);
    }
  }
  return out;
}

const files = readdirSync(I18N_DIR).filter(f => f.endsWith('.json')).sort();
if (files.length < 2) {
  console.error(`Expected at least 2 locale files in ${I18N_DIR}, found ${files.length}`);
  process.exit(1);
}

const locales = files.map(f => ({
  name: f.replace(/\.json$/, ''),
  keys: flatten(JSON.parse(readFileSync(join(I18N_DIR, f), 'utf8')))
}));

const reference = locales[0];
let mismatch = false;
for (const locale of locales.slice(1)) {
  const missingInLocale = [...reference.keys].filter(k => !locale.keys.has(k));
  const extraInLocale = [...locale.keys].filter(k => !reference.keys.has(k));
  if (missingInLocale.length > 0 || extraInLocale.length > 0) {
    mismatch = true;
    console.error(`\nKey mismatch between ${reference.name}.json and ${locale.name}.json:`);
    if (missingInLocale.length > 0) {
      console.error(`  Missing in ${locale.name}.json (${missingInLocale.length}):`);
      for (const k of missingInLocale) console.error(`    - ${k}`);
    }
    if (extraInLocale.length > 0) {
      console.error(`  Extra in ${locale.name}.json (${extraInLocale.length}):`);
      for (const k of extraInLocale) console.error(`    + ${k}`);
    }
  }
}

let backendMissing = false;
try {
  const mapperSrc = readFileSync(API_ERROR_MAPPER, 'utf8');
  const codes = new Set();
  const hashSetRegex = /HashSet<string>[\s\S]*?\{([\s\S]*?)\}/g;
  let m;
  while ((m = hashSetRegex.exec(mapperSrc)) !== null) {
    const block = m[1];
    const stringRegex = /"([a-z_]+)"/g;
    let s;
    while ((s = stringRegex.exec(block)) !== null) {
      codes.add(s[1]);
    }
  }
  const missingFromEn = [...codes].filter(c => !reference.keys.has(`error.${c}`));
  if (missingFromEn.length > 0) {
    backendMissing = true;
    console.error(`\nBackend codes missing from ${reference.name}.json (${missingFromEn.length}):`);
    for (const c of missingFromEn) console.error(`    - error.${c}`);
  } else {
    console.log(`Backend audit OK — ${codes.size} ApiErrorMapper codes all have error.<code> keys.`);
  }
} catch (err) {
  console.warn(`\nBackend audit skipped — could not read ${API_ERROR_MAPPER}: ${err.message}`);
}

if (mismatch || backendMissing) {
  process.exit(1);
}
console.log(`i18n parity OK — ${locales.length} locales, ${reference.keys.size} keys each.`);
