import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, firstValueFrom, of, tap } from 'rxjs';
import { TranslateService } from '@ngx-translate/core';
import { PrimeNG } from 'primeng/config';

import { DEFAULT_LOCALE, LOCALE_STORAGE_KEY, Locale, isLocale } from './locale.model';
import { PRIMENG_TRANSLATIONS } from './primeng-translations';
import { cyrillicToLatin } from './transliterate';

@Injectable({ providedIn: 'root' })
export class LanguageService {
  private readonly translate = inject(TranslateService);
  private readonly primeng = inject(PrimeNG);

  private readonly _currentLocale = signal<Locale>(this.readPersistedLocale());
  readonly currentLocale = this._currentLocale.asReadonly();
  readonly isCyrillic = computed(() => this._currentLocale() === 'sr-cyrl');

  // User-authored content is stored canonically in Cyrillic; the Latin view is
  // derived on the client. Both sr-latn and en render content in Latin (Latin
  // is closer to a non-Serbian reader); only sr-cyrl shows the canonical script.
  readonly shouldTransliterateContent = computed(() => this._currentLocale() !== 'sr-cyrl');

  // Single chokepoint for rendering user-authored content in the active script:
  // transliterates Cyrillic→Latin under sr-latn/en, passes through under sr-cyrl.
  // Used by TranslitPipe (plain text) and by TS callsites that embed content into
  // translate.instant() messages (confirm dialogs).
  transliterateContent(value: string): string {
    return this.shouldTransliterateContent() ? cyrillicToLatin(value) : value;
  }

  async loadInitialLocale(): Promise<void> {
    const locale = this._currentLocale();
    this.primeng.setTranslation(PRIMENG_TRANSLATIONS[locale]);
    await firstValueFrom(this.translate.use(locale));
  }

  setLocale(locale: Locale): Observable<unknown> {
    if (locale === this._currentLocale()) {
      return of(null);
    }
    this.writePersistedLocale(locale);
    this._currentLocale.set(locale);
    this.primeng.setTranslation(PRIMENG_TRANSLATIONS[locale]);
    return this.translate.use(locale).pipe(tap(() => {}));
  }

  private readPersistedLocale(): Locale {
    try {
      const raw = window.localStorage.getItem(LOCALE_STORAGE_KEY);
      if (raw === null) {
        return DEFAULT_LOCALE;
      }
      if (isLocale(raw)) {
        return raw;
      }
      console.warn(`[LanguageService] Ignoring malformed ${LOCALE_STORAGE_KEY} value: ${raw}`);
      return DEFAULT_LOCALE;
    } catch (err) {
      console.warn('[LanguageService] localStorage unavailable, falling back to default locale', err);
      return DEFAULT_LOCALE;
    }
  }

  private writePersistedLocale(locale: Locale): void {
    try {
      window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
    } catch (err) {
      console.warn('[LanguageService] Failed to persist locale to localStorage', err);
    }
  }
}
