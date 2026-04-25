import { Component, computed, inject } from '@angular/core';
import { Router } from '@angular/router';

import { Card } from 'primeng/card';
import { Button } from 'primeng/button';

import { AuthService } from '../../core/auth/auth.service';
import { TenantContextService } from '../../core/tenant-context';

@Component({
  selector: 'izvor-dashboard',
  imports: [Card, Button],
  template: `
    <div class="dashboard-page">
      <p-card header="Dashboard" styleClass="dashboard-card">
        <p>Welcome, {{ user()?.email }}</p>
        <p>Role: {{ user()?.role }}</p>
        <p>Tenant: {{ subdomain }}</p>

        <p-button
          label="Logout"
          severity="secondary"
          (onClick)="onLogout()"
          styleClass="dashboard-logout"
        />
      </p-card>
    </div>
  `,
  styles: [`
    .dashboard-page {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 1rem;
    }

    :host ::ng-deep .dashboard-card {
      width: 100%;
      max-width: 400px;
    }

    .dashboard-page p {
      margin: 0 0 0.5rem;
    }

    :host ::ng-deep .dashboard-logout {
      margin-top: 1rem;
    }
  `]
})
export class Dashboard {
  private readonly authService = inject(AuthService);
  private readonly tenantContext = inject(TenantContextService);
  private readonly router = inject(Router);

  readonly user = computed(() => this.authService.currentUser());
  readonly subdomain = this.tenantContext.subdomain;

  onLogout(): void {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}
