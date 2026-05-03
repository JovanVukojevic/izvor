import { Routes } from '@angular/router';

import { roleGuard } from '../../core/auth/role.guard';

export const CATEGORIES_ROUTES: Routes = [
  {
    path: '',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-list/category-list').then(m => m.CategoryList)
  },
  {
    path: 'new',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-form/category-form').then(m => m.CategoryForm)
  },
  {
    path: ':id/edit',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-form/category-form').then(m => m.CategoryForm)
  }
];
