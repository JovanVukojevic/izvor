import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { MessageService } from 'primeng/api';
import { catchError, throwError } from 'rxjs';

import { AuthService } from '../auth/auth.service';
import { ErrorResponse } from './models/error-response.model';

const AUTH_ENDPOINTS = ['/api/auth/login', '/api/auth/refresh', '/api/auth/logout'];

const DEAD_SESSION_CODES: ReadonlySet<string> = new Set([
  'tenant_mismatch',
  'no_active_user_in_session'
]);

export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const messageService = inject(MessageService);
  const authService = inject(AuthService);

  const isAuthRequest = AUTH_ENDPOINTS.some(path => req.url.endsWith(path));

  return next(req).pipe(
    catchError(error => {
      if (isAuthRequest || !(error instanceof HttpErrorResponse)) {
        return throwError(() => error);
      }
      if (error.status === 401) {
        return throwError(() => error);
      }

      const body = error.error as ErrorResponse | null | undefined;
      const matchedDeadSession =
        error.status === 403 &&
        ((body?.error !== undefined && DEAD_SESSION_CODES.has(body.error)) ||
          (body?.message !== undefined && DEAD_SESSION_CODES.has(body.message)));

      if (matchedDeadSession) {
        const isTenantMismatch =
          body?.error === 'tenant_mismatch' || body?.message === 'tenant_mismatch';
        const detail = isTenantMismatch
          ? 'Session does not match this tenant.'
          : 'Session expired. Please sign in again.';
        messageService.add({ severity: 'error', summary: 'Signed out', detail });
        authService.logout();
        return throwError(() => error);
      }

      if (error.status >= 500) {
        messageService.add({
          severity: 'error',
          summary: 'Server error',
          detail: body?.message ?? 'Something went wrong. Please try again.'
        });
        return throwError(() => error);
      }

      if (error.status === 429) {
        messageService.add({
          severity: 'warn',
          summary: 'Too many requests',
          detail: body?.message ?? 'Please slow down and try again shortly.'
        });
        return throwError(() => error);
      }

      if (error.status === 0) {
        messageService.add({
          severity: 'error',
          summary: 'Network error',
          detail: 'Could not reach the server. Check your connection.'
        });
        return throwError(() => error);
      }

      return throwError(() => error);
    })
  );
};
