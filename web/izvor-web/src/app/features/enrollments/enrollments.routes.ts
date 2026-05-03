import { Routes } from '@angular/router';

export const ENROLLMENTS_ROUTES: Routes = [
  {
    path: '',
    title: 'My Enrollments · Izvor',
    loadComponent: () =>
      import('./my-enrollments/my-enrollments').then(m => m.MyEnrollments)
  }
];
