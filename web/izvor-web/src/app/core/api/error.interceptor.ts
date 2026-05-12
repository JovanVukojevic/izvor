import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { MessageService } from 'primeng/api';
import { TranslateService } from '@ngx-translate/core';
import { catchError, throwError } from 'rxjs';

import { AuthService } from '../auth/auth.service';
import { ErrorResponse } from './models/error-response.model';
import { translateApiErrorCode } from './translate-api-error';

const AUTH_ENDPOINTS = ['/api/auth/login', '/api/auth/refresh', '/api/auth/logout'];

const DEAD_SESSION_CODES: ReadonlySet<string> = new Set([
  'tenant_mismatch',
  'no_active_user_in_session'
]);

export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const messageService = inject(MessageService);
  const authService = inject(AuthService);
  const translate = inject(TranslateService);

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
        const detailKey = isTenantMismatch
          ? 'error.session.tenantMismatchDetail'
          : 'error.session.expiredDetail';
        messageService.add({
          severity: 'error',
          summary: translate.instant('error.session.signedOutSummary'),
          detail: translate.instant(detailKey)
        });
        authService.logout();
        return throwError(() => error);
      }

      if (error.status >= 500) {
        messageService.add({
          severity: 'error',
          summary: translate.instant('error.server.summary'),
          detail: translateApiErrorCode(translate, body?.message, 'error.server.generic')
        });
        return throwError(() => error);
      }

      if (error.status === 429) {
        messageService.add({
          severity: 'warn',
          summary: translate.instant('error.network.tooManyRequestsSummary'),
          detail: translateApiErrorCode(translate, body?.message, 'error.network.tooManyRequestsDetail')
        });
        return throwError(() => error);
      }

      if (error.status === 0) {
        messageService.add({
          severity: 'error',
          summary: translate.instant('error.network.summary'),
          detail: translate.instant('error.network.detail')
        });
        return throwError(() => error);
      }

      return throwError(() => error);
    })
  );
};
