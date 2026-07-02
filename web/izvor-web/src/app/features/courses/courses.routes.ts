import { Routes } from '@angular/router';

import { roleGuard } from '../../core/auth/role.guard';

export const COURSES_ROUTES: Routes = [
  {
    path: '',
    title: 'title.courses',
    loadComponent: () => import('./course-list/course-list').then(m => m.CourseList)
  },
  {
    path: 'new',
    title: 'title.courseNew',
    canActivate: [roleGuard],
    data: { minRole: 'author' },
    loadComponent: () => import('./course-form/course-form').then(m => m.CourseForm)
  },
  {
    path: ':id',
    loadComponent: () => import('./course-detail/course-detail').then(m => m.CourseDetail)
  },
  {
    path: ':id/edit',
    canActivate: [roleGuard],
    data: { minRole: 'author' },
    loadComponent: () => import('./course-form/course-form').then(m => m.CourseForm)
  },
  {
    path: ':id/lessons/new',
    title: 'title.lessonNew',
    canActivate: [roleGuard],
    data: { minRole: 'author' },
    loadComponent: () => import('../lessons/lesson-form/lesson-form').then(m => m.LessonForm)
  },
  {
    path: ':id/lessons/:lessonId',
    loadComponent: () => import('../lessons/lesson-detail/lesson-detail').then(m => m.LessonDetail)
  },
  {
    path: ':id/lessons/:lessonId/edit',
    canActivate: [roleGuard],
    data: { minRole: 'author' },
    loadComponent: () => import('../lessons/lesson-form/lesson-form').then(m => m.LessonForm)
  }
];
