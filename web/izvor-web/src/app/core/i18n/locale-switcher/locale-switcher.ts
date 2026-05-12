import { Component, computed, inject, input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { SelectButton } from 'primeng/selectbutton';

import { LanguageService } from '../language.service';
import { LOCALES, Locale } from '../locale.model';

interface LocaleOption {
  label: string;
  value: Locale;
}

// Locale labels render in each language's own script so a user lost in a
// foreign UI can still recognize their target locale.
const LOCALE_LABELS: Record<Locale, string> = {
  'en': 'English',
  'sr-latn': 'Srpski (latinica)',
  'sr-cyrl': 'Српски (ћирилица)'
};

@Component({
  selector: 'izvor-locale-switcher',
  imports: [FormsModule, SelectButton],
  template: `
    <p-selectButton
      [options]="options()"
      [ngModel]="languageService.currentLocale()"
      (onChange)="onChange($event.value)"
      optionLabel="label"
      optionValue="value"
      [allowEmpty]="false"
      [size]="size()"
    />
  `
})
export class LocaleSwitcher {
  protected readonly languageService = inject(LanguageService);

  readonly size = input<'small' | 'large'>('small');

  readonly options = computed<LocaleOption[]>(() =>
    LOCALES.map(locale => ({ label: LOCALE_LABELS[locale], value: locale }))
  );

  onChange(locale: Locale): void {
    this.languageService.setLocale(locale).subscribe();
  }
}
