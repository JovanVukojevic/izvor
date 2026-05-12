import { ChangeDetectorRef, OnDestroy, Pipe, PipeTransform, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { Subscription } from 'rxjs';

import { UserRole } from '../auth/role.utils';

@Pipe({ name: 'roleLabel', pure: false })
export class RoleLabelPipe implements PipeTransform, OnDestroy {
  private readonly translate = inject(TranslateService);
  private readonly cdr = inject(ChangeDetectorRef);
  private readonly subscriptions: Subscription[] = [];
  private subscribed = false;
  private cachedRole: UserRole | null | undefined = undefined;
  private cachedValue = '';

  transform(role: UserRole | null | undefined): string {
    this.ensureSubscribed();
    if (role === this.cachedRole) {
      return this.cachedValue;
    }
    this.cachedRole = role;
    this.cachedValue = role ? this.translate.instant(`role.${role}`) : '';
    return this.cachedValue;
  }

  ngOnDestroy(): void {
    for (const sub of this.subscriptions) sub.unsubscribe();
  }

  private ensureSubscribed(): void {
    if (this.subscribed) return;
    this.subscribed = true;
    const refresh = () => {
      this.cachedRole = undefined;
      this.cdr.markForCheck();
    };
    this.subscriptions.push(this.translate.onLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onFallbackLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onTranslationChange.subscribe(refresh));
  }
}
