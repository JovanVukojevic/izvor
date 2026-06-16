import { ChangeDetectorRef, OnDestroy, Pipe, PipeTransform, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { Subscription } from 'rxjs';

import { LanguageService } from './language.service';

// Renders user-authored content (Cyrillic canonical) in the active script:
// Latin under sr-latn/en, untouched under sr-cyrl. Impure + cache, modelled on
// the label pipes (role-label, enrollment-status-label) so it re-evaluates on
// locale change under OnPush — setLocale() fires translate.use(), which emits
// onLangChange, invalidating the cache.
@Pipe({ name: 'translit', pure: false })
export class TranslitPipe implements PipeTransform, OnDestroy {
  private readonly language = inject(LanguageService);
  private readonly translate = inject(TranslateService);
  private readonly cdr = inject(ChangeDetectorRef);
  private readonly subscriptions: Subscription[] = [];
  private subscribed = false;
  private cachedInput: string | null | undefined = undefined;
  private cachedValue = '';

  transform(value: string | null | undefined): string {
    this.ensureSubscribed();
    if (value === this.cachedInput) {
      return this.cachedValue;
    }
    this.cachedInput = value;
    this.cachedValue = this.language.transliterateContent(value ?? '');
    return this.cachedValue;
  }

  ngOnDestroy(): void {
    for (const sub of this.subscriptions) sub.unsubscribe();
  }

  private ensureSubscribed(): void {
    if (this.subscribed) return;
    this.subscribed = true;
    const refresh = () => {
      this.cachedInput = undefined;
      this.cdr.markForCheck();
    };
    this.subscriptions.push(this.translate.onLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onTranslationChange.subscribe(refresh));
  }
}
