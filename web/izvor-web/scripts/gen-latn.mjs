import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { generateLatn, serialize } from './lib/translit.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const I18N_DIR = join(__dirname, '..', 'public', 'i18n');
const CYRL = join(I18N_DIR, 'sr-cyrl.json');
const LATN = join(I18N_DIR, 'sr-latn.json');
const OVERRIDES = join(__dirname, 'sr-latn.overrides.json');

const cyrl = JSON.parse(readFileSync(CYRL, 'utf8'));
const overrides = existsSync(OVERRIDES) ? JSON.parse(readFileSync(OVERRIDES, 'utf8')) : {};

writeFileSync(LATN, serialize(generateLatn(cyrl, overrides)), 'utf8');

const overrideCount = Object.keys(overrides).length;
console.log(`Generated sr-latn.json from sr-cyrl.json (${overrideCount} override${overrideCount === 1 ? '' : 's'}).`);
