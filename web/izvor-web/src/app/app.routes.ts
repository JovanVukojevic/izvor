import { Routes } from '@angular/router';

import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: 'login', title: 'Login · Izvor', loadComponent: () => import('./features/login/login').then(m => m.Login) },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./layouts/authenticated-shell/authenticated-shell').then(m => m.AuthenticatedShell),
    children: [
      {
        path: 'dashboard',
        title: 'Dashboard · Izvor',
        loadComponent: () => import('./features/dashboard/dashboard').then(m => m.Dashboard)
      },
      {
        path: 'categories',
        loadChildren: () =>
          import('./features/categories/categories.routes').then(m => m.CATEGORIES_ROUTES)
      },
      {
        path: 'courses',
        loadChildren: () =>
          import('./features/courses/courses.routes').then(m => m.COURSES_ROUTES)
      },
      {
        path: 'my-enrollments',
        loadChildren: () =>
          import('./features/enrollments/enrollments.routes').then(m => m.ENROLLMENTS_ROUTES)
      },
      { path: '', pathMatch: 'full', redirectTo: 'dashboard' }
    ]
  },
  { path: '**', redirectTo: '/dashboard' }
];
