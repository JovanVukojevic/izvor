import { ChangeDetectorRef, OnDestroy, Pipe, PipeTransform, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { Subscription } from 'rxjs';

@Pipe({ name: 'courseActivityLabel', pure: false })
export class CourseActivityLabelPipe implements PipeTransform, OnDestroy {
  private readonly translate = inject(TranslateService);
  private readonly cdr = inject(ChangeDetectorRef);
  private readonly subscriptions: Subscription[] = [];
  private subscribed = false;
  private cachedActive: boolean | null | undefined = undefined;
  private cachedValue = '';

  transform(isActive: boolean | null | undefined): string {
    this.ensureSubscribed();
    if (isActive === this.cachedActive) {
      return this.cachedValue;
    }
    this.cachedActive = isActive;
    const key = isActive ? 'course.activity.active' : 'course.activity.inactive';
    this.cachedValue = this.translate.instant(key);
    return this.cachedValue;
  }

  ngOnDestroy(): void {
    for (const sub of this.subscriptions) sub.unsubscribe();
  }

  private ensureSubscribed(): void {
    if (this.subscribed) return;
    this.subscribed = true;
    const refresh = () => {
      this.cachedActive = undefined;
      this.cdr.markForCheck();
    };
    this.subscriptions.push(this.translate.onLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onFallbackLangChange.subscribe(refresh));
    this.subscriptions.push(this.translate.onTranslationChange.subscribe(refresh));
  }
}
