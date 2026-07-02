import { Injectable, OnDestroy, inject } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterStateSnapshot, TitleStrategy } from '@angular/router';
import { TranslateService } from '@ngx-translate/core';
import { Subscription } from 'rxjs';

const TITLE_SUFFIX = ' · Izvor';

// Resolves the route title as an i18n key (e.g. 'title.myEnrollments') and sets
// '<translated label> · Izvor'. Title-less routes are left untouched so the
// dynamic pages that set their own title via Title.setTitle (course/lesson
// detail + edit) keep working. Re-titles on locale switch without navigation:
// the onLangChange subscription is created ONCE in the constructor — updateTitle
// only re-runs the titling, never subscribes (it fires on every navigation).
@Injectable()
export class TranslatedTitleStrategy extends TitleStrategy implements OnDestroy {
  private readonly title = inject(Title);
  private readonly translate = inject(TranslateService);
  private currentRouterState: RouterStateSnapshot | null = null;
  private readonly langChangeSub: Subscription;

  constructor() {
    super();
    this.langChangeSub = this.translate.onLangChange.subscribe(() => {
      if (this.currentRouterState) {
        this.updateTitle(this.currentRouterState);
      }
    });
  }

  override updateTitle(routerState: RouterStateSnapshot): void {
    this.currentRouterState = routerState;
    const key = this.buildTitle(routerState);
    if (key === undefined) {
      return;
    }
    this.title.setTitle(`${this.translate.instant(key)}${TITLE_SUFFIX}`);
  }

  ngOnDestroy(): void {
    this.langChangeSub.unsubscribe();
  }
}
