// Deterministic Serbian Cyrillic → Latin transliteration (1:1 with digraphs).
// Presentation-only: the DB stores canonical Cyrillic; this derives the Latin
// view on the client. Cyrillic→Latin is the lossless direction (љ/њ/џ map
// unambiguously to lj/nj/dž); the reverse is ambiguous and never performed.
//
// Build-time twin: scripts/lib/translit.mjs carries the same table to generate
// sr-latn.json from sr-cyrl.json. Keep the two in sync (the Serbian alphabet is
// fixed, so drift risk is low).

const MAP: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', ђ: 'đ', е: 'e', ж: 'ž', з: 'z',
  и: 'i', ј: 'j', к: 'k', л: 'l', љ: 'lj', м: 'm', н: 'n', њ: 'nj', о: 'o',
  п: 'p', р: 'r', с: 's', т: 't', ћ: 'ć', у: 'u', ф: 'f', х: 'h', ц: 'c',
  ч: 'č', џ: 'dž', ш: 'š',
  А: 'A', Б: 'B', В: 'V', Г: 'G', Д: 'D', Ђ: 'Đ', Е: 'E', Ж: 'Ž', З: 'Z',
  И: 'I', Ј: 'J', К: 'K', Л: 'L', М: 'M', Н: 'N', О: 'O', П: 'P', Р: 'R',
  С: 'S', Т: 'T', Ћ: 'Ć', У: 'U', Ф: 'F', Х: 'H', Ц: 'C', Ч: 'Č', Ш: 'Š'
};

// Uppercase digraphs cased by neighbour: Љубав→Ljubav, ЉУБАВ→LJUBAV, ЛЕЊ→LENJ.
const DIGRAPH_CAPITALS: Record<string, { title: string; upper: string }> = {
  Љ: { title: 'Lj', upper: 'LJ' },
  Њ: { title: 'Nj', upper: 'NJ' },
  Џ: { title: 'Dž', upper: 'DŽ' }
};

const UPPER_CYRILLIC = new Set('АБВГДЂЕЖЗИЈКЛЉМНЊОПРСТЋУФХЦЧЏШ');

export function cyrillicToLatin(input: string): string {
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
