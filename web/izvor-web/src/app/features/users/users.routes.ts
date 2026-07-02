import { Routes } from '@angular/router';

import { roleGuard } from '../../core/auth/role.guard';

export const USERS_ROUTES: Routes = [
  {
    path: '',
    title: 'title.users',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./user-list/user-list').then(m => m.UserList)
  },
  {
    path: 'new',
    title: 'title.userNew',
    canActivate: [roleGuard],
    data: { minRole: 'admin' },
    loadComponent: () =>
      import('./user-form/user-form').then(m => m.UserForm)
  }
];
