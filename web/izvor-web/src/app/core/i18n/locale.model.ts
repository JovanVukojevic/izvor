export type Locale = 'en' | 'sr-latn' | 'sr-cyrl';

// 'en' is intentionally hidden from the language switcher for the thesis
// (the application language is Serbian, in two scripts). Restore after thesis
// defense: re-add 'en' to this array. en.json and the 'en' Locale type stay,
// so English is simply never offered or resolved until then.
export const LOCALES: readonly Locale[] = [/* 'en', restore after thesis defense */ 'sr-latn', 'sr-cyrl'] as const;

// Izvor's application language is Serbian; Cyrillic is the canonical script
// (content is authored in Cyrillic, Latin is derived), so sr-cyrl is the
// default. navigator.language is intentionally not consulted — mapping a wide
// range of browser locales (en-US, de-DE, bs-BA, sr-RS, ...) to our locales
// would require non-trivial normalization and still wouldn't distinguish latin
// from cyrillic for sr-*. Hardcoding keeps initial UX stable.
export const DEFAULT_LOCALE: Locale = 'sr-cyrl';

export const LOCALE_STORAGE_KEY = 'izvor.locale';

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value);
}
