import { ChangeDetectorRef, OnDestroy, Pipe, PipeTransform, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { Subscription } from 'rxjs';

import { EnrollmentStatus } from '../api/models/enrollment.model';

@Pipe({ name: 'enrollmentStatusLabel', pure: false })
export class EnrollmentStatusLabelPipe implements PipeTransform, OnDestroy {
  private readonly translate = inject(TranslateService);
  private readonly cdr = inject(ChangeDetectorRef);
  private readonly subscriptions: Subscription[] = [];
  private subscribed = false;
  private cachedStatus: EnrollmentStatus | null | undefined = undefined;
  private cachedValue = '';

  transform(status: EnrollmentStatus | null | undefined): string {
    this.ensureSubscribed();
    if (status === this.cachedStatus) {
      return this.cachedValue;
    }
    this.cachedStatus = status;
    this.cachedValue = status ? this.translate.instant(`enrollment.status.${status}`) : '';
    return this.cachedValue;
  }

  ngOnDestroy(): void {
    for (const sub of this.subscriptions) sub.unsubscribe();
  }

  private ensureSubscribed(): void {
    if (this.subscribed) return;
    this.subscribed = true;
    const refresh = () => {
      this.cachedStatus = undefined;
      this.cdr.markForCheck();
    };
    this.subscriptions.push(this.translate.onLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onFallbackLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onTranslationChange.subscribe(refresh));
  }
}
