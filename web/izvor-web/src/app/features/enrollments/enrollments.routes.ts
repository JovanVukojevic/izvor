import { Routes } from '@angular/router';

export const ENROLLMENTS_ROUTES: Routes = [
  {
    path: '',
    title: 'title.myEnrollments',
    loadComponent: () =>
      import('./my-enrollments/my-enrollments').then(m => m.MyEnrollments)
  }
];
