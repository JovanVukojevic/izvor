import { Routes } from '@angular/router';

import { roleGuard } from '../../core/auth/role.guard';

export const CATEGORIES_ROUTES: Routes = [
  {
    path: '',
    title: 'Categories · Izvor',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-list/category-list').then(m => m.CategoryList)
  },
  {
    path: 'new',
    title: 'New Category · Izvor',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-form/category-form').then(m => m.CategoryForm)
  },
  {
    path: ':id/edit',
    title: 'Edit Category · Izvor',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./category-form/category-form').then(m => m.CategoryForm)
  }
];
