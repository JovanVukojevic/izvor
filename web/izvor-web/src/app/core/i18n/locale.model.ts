export type Locale = 'en' | 'sr-latn' | 'sr-cyrl';

export const LOCALES: readonly Locale[] = ['en', 'sr-latn', 'sr-cyrl'] as const;

// Izvor targets the Serbian market; sr-latn is the predictable default for the
// primary audience. navigator.language is intentionally not consulted — mapping
// a wide range of browser locales (en-US, de-DE, bs-BA, sr-RS, ...) to one of
// our three locales would require non-trivial normalization and still wouldn't
// distinguish latin from cyrillic for sr-*. Hardcoding keeps initial UX stable.
export const DEFAULT_LOCALE: Locale = 'sr-latn';

export const LOCALE_STORAGE_KEY = 'izvor.locale';

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value);
}
