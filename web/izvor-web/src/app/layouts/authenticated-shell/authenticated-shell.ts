import { Component, computed, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { Button } from 'primeng/button';

import { AuthService } from '../../core/auth/auth.service';
import { TenantContextService } from '../../core/tenant-context';
import { RequiresRoleDirective } from '../../core/auth/role.directive';

@Component({
  selector: 'izvor-authenticated-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, Button, RequiresRoleDirective],
  template: `
    <div class="shell">
      <header class="shell-topbar">
        <div class="shell-brand">
          <span class="shell-brand-name">Izvor</span>
          @if (tenantLabel(); as label) {
            <span class="shell-brand-tenant">· {{ label }}</span>
          }
        </div>

        <nav class="shell-nav">
          <a routerLink="/dashboard" routerLinkActive="shell-nav-active">Dashboard</a>
          <a routerLink="/courses" routerLinkActive="shell-nav-active">Browse Courses</a>
          <a routerLink="/my-enrollments" routerLinkActive="shell-nav-active">My Enrollments</a>
          <a *izvorRequiresRole="'author'" routerLink="/courses/new" routerLinkActive="shell-nav-active">Create Course</a>
          <a *izvorRequiresRole="'admin'" routerLink="/categories" routerLinkActive="shell-nav-active">Manage Categories</a>
        </nav>

        <div class="shell-user">
          @if (user(); as u) {
            <span class="shell-user-meta">{{ u.email }} · {{ u.role }}</span>
          }
          <p-button label="Logout" severity="secondary" size="small" (onClick)="onLogout()" />
        </div>
      </header>

      <main class="shell-main">
        <router-outlet />
      </main>
    </div>
  `,
  styles: [`
    .shell {
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    .shell-topbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1.5rem;
      padding: 0.75rem 1.5rem;
      border-bottom: 1px solid var(--p-content-border-color, #e5e7eb);
      background: var(--p-content-background, #ffffff);
      flex-wrap: wrap;
    }

    .shell-brand {
      font-size: 1.125rem;
      font-weight: 600;
    }

    .shell-brand-tenant {
      font-weight: 400;
      color: var(--p-text-muted-color, #6b7280);
      margin-left: 0.25rem;
    }

    .shell-nav {
      display: flex;
      gap: 1rem;
      flex: 1;
      flex-wrap: wrap;
    }

    .shell-nav a {
      color: var(--p-text-color, #111827);
      text-decoration: none;
      padding: 0.375rem 0.5rem;
      border-radius: 4px;
    }

    .shell-nav a:hover {
      background: var(--p-content-hover-background, #f3f4f6);
    }

    .shell-nav-active {
      background: var(--p-highlight-background, #eef2ff);
      color: var(--p-highlight-color, #3730a3);
      font-weight: 500;
    }

    .shell-user {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }

    .shell-user-meta {
      font-size: 0.875rem;
      color: var(--p-text-muted-color, #6b7280);
    }

    .shell-main {
      flex: 1;
      padding: 1.5rem;
      max-width: 1200px;
      width: 100%;
      align-self: center;
      box-sizing: border-box;
    }
  `]
})
export class AuthenticatedShell {
  private readonly auth = inject(AuthService);
  private readonly tenant = inject(TenantContextService);
  private readonly router = inject(Router);

  readonly user = this.auth.currentUser;
  readonly tenantLabel = computed(() => {
    const sub = this.tenant.subdomain;
    if (!sub) return null;
    return sub.charAt(0).toUpperCase() + sub.slice(1);
  });

  onLogout(): void {
    this.auth.logout();
    this.router.navigate(['/login']);
  }
}
