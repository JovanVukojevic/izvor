import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, firstValueFrom, of, tap } from 'rxjs';
import { TranslateService } from '@ngx-translate/core';
import { PrimeNG } from 'primeng/config';

import { DEFAULT_LOCALE, LOCALE_STORAGE_KEY, Locale, isLocale } from './locale.model';
import { PRIMENG_TRANSLATIONS } from './primeng-translations';

@Injectable({ providedIn: 'root' })
export class LanguageService {
  private readonly translate = inject(TranslateService);
  private readonly primeng = inject(PrimeNG);

  private readonly _currentLocale = signal<Locale>(this.readPersistedLocale());
  readonly currentLocale = this._currentLocale.asReadonly();
  readonly isCyrillic = computed(() => this._currentLocale() === 'sr-cyrl');

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
