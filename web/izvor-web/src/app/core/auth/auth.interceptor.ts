import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { AuthService } from './auth.service';

const LOGIN_PATH = '/api/auth/login';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  const isLoginRequest = req.url.endsWith(LOGIN_PATH);
  const token = authService.getAccessToken();

  const outgoing = token !== null && !isLoginRequest
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  return next(outgoing).pipe(
    catchError(error => {
      if (error instanceof HttpErrorResponse && error.status === 401 && !isLoginRequest) {
        authService.logout();
        router.navigate(['/login']);
      }
      return throwError(() => error);
    })
  );
};
