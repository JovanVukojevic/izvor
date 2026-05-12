import { Component, inject } from '@angular/core';

import { Card } from 'primeng/card';
import { TranslateModule } from '@ngx-translate/core';

import { AuthService } from '../../core/auth/auth.service';
import { RoleLabelPipe } from '../../core/i18n/role-label.pipe';

@Component({
  selector: 'izvor-dashboard',
  imports: [Card, TranslateModule, RoleLabelPipe],
  template: `
    <div class="dashboard">
      <p-card [header]="'dashboard.cardHeader' | translate">
        @if (user(); as u) {
          <p>{{ 'dashboard.welcome' | translate: { email: u.email } }}</p>
          <p class="dashboard-meta">{{ 'dashboard.roleLine' | translate: { role: (u.role | roleLabel) } }}</p>
        }
        <p>{{ 'dashboard.body' | translate }}</p>
      </p-card>
    </div>
  `,
  styles: [`
    .dashboard {
      max-width: 800px;
    }

    .dashboard-meta {
      color: var(--p-text-muted-color, #6b7280);
      margin-bottom: 1rem;
    }
  `]
})
export class Dashboard {
  private readonly auth = inject(AuthService);
  readonly user = this.auth.currentUser;
}
