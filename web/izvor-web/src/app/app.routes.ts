import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: 'login', loadComponent: () => import('./features/login/login').then(m => m.Login) },
  { path: 'dashboard', loadComponent: () => import('./dashboard-placeholder').then(m => m.DashboardPlaceholder) },
  { path: '', pathMatch: 'full', redirectTo: '/login' },
  { path: '**', redirectTo: '/login' }
];
