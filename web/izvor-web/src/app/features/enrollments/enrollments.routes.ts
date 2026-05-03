import { Routes } from '@angular/router';

export const ENROLLMENTS_ROUTES: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./my-enrollments/my-enrollments').then(m => m.MyEnrollments)
  }
];
