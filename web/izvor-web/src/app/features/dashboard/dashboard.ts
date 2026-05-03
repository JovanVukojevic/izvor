import { Component, inject } from '@angular/core';

import { Card } from 'primeng/card';

import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'izvor-dashboard',
  imports: [Card],
  template: `
    <div class="dashboard">
      <p-card header="Welcome">
        @if (user(); as u) {
          <p>Welcome, <strong>{{ u.email }}</strong></p>
          <p class="dashboard-meta">Role: {{ u.role }}</p>
        }
        <p>Use the navigation above to browse courses, manage your enrollments, or — if you have permission — create courses and manage categories.</p>
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
