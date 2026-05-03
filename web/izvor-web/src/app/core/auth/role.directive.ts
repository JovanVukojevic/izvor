import {
  Directive,
  Input,
  TemplateRef,
  ViewContainerRef,
  effect,
  inject,
  signal
} from '@angular/core';

import { AuthService } from './auth.service';
import { UserRole, hasRole } from './role.utils';

@Directive({
  selector: '[izvorRequiresRole]'
})
export class RequiresRoleDirective {
  private readonly templateRef = inject(TemplateRef<unknown>);
  private readonly viewContainer = inject(ViewContainerRef);
  private readonly auth = inject(AuthService);

  private readonly required = signal<UserRole | null>(null);
  private rendered = false;

  constructor() {
    effect(() => {
      const required = this.required();
      const actual = this.auth.currentUser()?.role;
      const allowed = required !== null && hasRole(actual, required);
      if (allowed && !this.rendered) {
        this.viewContainer.createEmbeddedView(this.templateRef);
        this.rendered = true;
      } else if (!allowed && this.rendered) {
        this.viewContainer.clear();
        this.rendered = false;
      }
    });
  }

  @Input({ required: true })
  set izvorRequiresRole(value: UserRole) {
    this.required.set(value);
  }
}
