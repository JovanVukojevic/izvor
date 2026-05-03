import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, switchMap, throwError } from 'rxjs';

import { AuthService } from './auth.service';

const AUTH_ENDPOINTS = ['/api/auth/login', '/api/auth/refresh', '/api/auth/logout'];

function isAuthEndpoint(url: string): boolean {
  return AUTH_ENDPOINTS.some(path => url.endsWith(path));
}

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (isAuthEndpoint(req.url)) {
    return next(req);
  }

  const token = authService.getAccessToken();
  const outgoing = token !== null
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  return next(outgoing).pipe(
    catchError((error: unknown) => {
      if (!(error instanceof HttpErrorResponse) || error.status !== 401) {
        return throwError(() => error);
      }
      return authService.refreshAccessToken().pipe(
        switchMap(newToken => {
          const retry = req.clone({ setHeaders: { Authorization: `Bearer ${newToken}` } });
          return next(retry);
        }),
        catchError(refreshErr => {
          authService.logoutLocal();
          router.navigate(['/login']);
          return throwError(() => refreshErr);
        })
      );
    })
  );
};
