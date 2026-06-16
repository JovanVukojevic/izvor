// Build-time twin of src/app/core/i18n/transliterate.ts — same Serbian
// Cyrillic→Latin table — used to generate sr-latn.json from sr-cyrl.json and to
// verify it stays in sync. Keep the two tables aligned (the alphabet is fixed,
// so drift risk is low).

const MAP = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', ђ: 'đ', е: 'e', ж: 'ž', з: 'z',
  и: 'i', ј: 'j', к: 'k', л: 'l', љ: 'lj', м: 'm', н: 'n', њ: 'nj', о: 'o',
  п: 'p', р: 'r', с: 's', т: 't', ћ: 'ć', у: 'u', ф: 'f', х: 'h', ц: 'c',
  ч: 'č', џ: 'dž', ш: 'š',
  А: 'A', Б: 'B', В: 'V', Г: 'G', Д: 'D', Ђ: 'Đ', Е: 'E', Ж: 'Ž', З: 'Z',
  И: 'I', Ј: 'J', К: 'K', Л: 'L', М: 'M', Н: 'N', О: 'O', П: 'P', Р: 'R',
  С: 'S', Т: 'T', Ћ: 'Ć', У: 'U', Ф: 'F', Х: 'H', Ц: 'C', Ч: 'Č', Ш: 'Š'
};

const DIGRAPH_CAPITALS = {
  Љ: { title: 'Lj', upper: 'LJ' },
  Њ: { title: 'Nj', upper: 'NJ' },
  Џ: { title: 'Dž', upper: 'DŽ' }
};

const UPPER_CYRILLIC = new Set('АБВГДЂЕЖЗИЈКЛЉМНЊОПРСТЋУФХЦЧЏШ');

export function cyrillicToLatin(input) {
  if (!input) return input;
  let out = '';
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    const digraph = DIGRAPH_CAPITALS[ch];
    if (digraph) {
      const prev = input[i - 1];
      const next = input[i + 1];
      const allCaps =
        (prev !== undefined && UPPER_CYRILLIC.has(prev)) ||
        (next !== undefined && UPPER_CYRILLIC.has(next));
      out += allCaps ? digraph.upper : digraph.title;
      continue;
    }
    out += MAP[ch] ?? ch;
  }
  return out;
}

// Recursively transliterate every leaf string of `cyrl`, preserving structure
// and key order. An override (keyed by dot-path) replaces the mechanical result
// for keys where transliteration would be wrong.
export function generateLatn(cyrl, overrides = {}, prefix = '') {
  if (cyrl === null || typeof cyrl !== 'object' || Array.isArray(cyrl)) {
    return cyrl;
  }
  const out = {};
  for (const [key, value] of Object.entries(cyrl)) {
    const path = prefix === '' ? key : `${prefix}.${key}`;
    if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      out[key] = generateLatn(value, overrides, path);
    } else if (typeof value === 'string') {
      out[key] = Object.prototype.hasOwnProperty.call(overrides, path)
        ? overrides[path]
        : cyrillicToLatin(value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

export function serialize(obj) {
  return `${JSON.stringify(obj, null, 2)}\n`;
}
