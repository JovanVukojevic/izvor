import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, catchError, finalize, map, shareReplay, tap, throwError } from 'rxjs';

import { API_BASE_URL } from '../api-base-url.token';
import { AuthResponse, LoginRequest, UserInfo } from './models';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);
  private readonly router = inject(Router);

  private accessToken: string | null = null;
  private refreshInFlight$: Observable<string> | null = null;

  private readonly _currentUser = signal<UserInfo | null>(null);
  readonly currentUser = this._currentUser.asReadonly();
  readonly isAuthenticated = computed(() => this._currentUser() !== null);

  getAccessToken(): string | null {
    return this.accessToken;
  }

  login(request: LoginRequest): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiBaseUrl}/api/auth/login`, request, { withCredentials: true })
      .pipe(tap(response => this.applyAuthResponse(response)));
  }

  fetchCurrentUser(): Observable<UserInfo> {
    return this.http
      .get<UserInfo>(`${this.apiBaseUrl}/api/me`)
      .pipe(tap(user => this._currentUser.set(user)));
  }

  refreshAccessToken(): Observable<string> {
    if (this.refreshInFlight$ !== null) {
      return this.refreshInFlight$;
    }
    this.refreshInFlight$ = this.http
      .post<AuthResponse>(`${this.apiBaseUrl}/api/auth/refresh`, {}, { withCredentials: true })
      .pipe(
        tap(response => this.applyAuthResponse(response)),
        map(response => response.accessToken),
        catchError(err => {
          this.clearLocalState();
          return throwError(() => err);
        }),
        finalize(() => { this.refreshInFlight$ = null; }),
        shareReplay(1)
      );
    return this.refreshInFlight$;
  }

  logout(): void {
    this.http
      .post(`${this.apiBaseUrl}/api/auth/logout`, {}, { withCredentials: true })
      .subscribe({ next: () => {}, error: () => {} });
    this.clearLocalState();
    this.router.navigate(['/login']);
  }

  logoutLocal(): void {
    this.clearLocalState();
  }

  private applyAuthResponse(response: AuthResponse): void {
    this.accessToken = response.accessToken;
    this._currentUser.set(response.user);
  }

  private clearLocalState(): void {
    this.accessToken = null;
    this._currentUser.set(null);
    this.refreshInFlight$ = null;
  }
}
