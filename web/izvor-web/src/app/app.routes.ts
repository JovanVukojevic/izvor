import { Routes } from '@angular/router';

import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: 'login', title: 'title.login', loadComponent: () => import('./features/login/login').then(m => m.Login) },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./layouts/authenticated-shell/authenticated-shell').then(m => m.AuthenticatedShell),
    children: [
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
      {
        path: 'users',
        loadChildren: () =>
          import('./features/users/users.routes').then(m => m.USERS_ROUTES)
      },
      { path: '', pathMatch: 'full', redirectTo: 'courses' }
    ]
  },
  { path: '**', redirectTo: '/courses' }
];
