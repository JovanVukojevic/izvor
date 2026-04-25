import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { API_BASE_URL } from '../api-base-url.token';
import { LoginRequest, LoginResponse, UserInfo } from './models';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private static readonly ACCESS_TOKEN_KEY = 'izvor.accessToken';
  private static readonly USER_KEY = 'izvor.user';

  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  private readonly _currentUser = signal<UserInfo | null>(null);
  private _accessToken: string | null = null;

  readonly currentUser = this._currentUser.asReadonly();
  readonly isAuthenticated = computed(() => this._currentUser() !== null);

  constructor() {
    this.hydrateFromSessionStorage();
  }

  getAccessToken(): string | null {
    return this._accessToken;
  }

  login(request: LoginRequest): Observable<LoginResponse> {
    return this.http
      .post<LoginResponse>(`${this.apiBaseUrl}/api/auth/login`, request)
      .pipe(tap(response => this.persistSession(response)));
  }

  logout(): void {
    sessionStorage.removeItem(AuthService.ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(AuthService.USER_KEY);
    this._accessToken = null;
    this._currentUser.set(null);
  }

  private persistSession(response: LoginResponse): void {
    sessionStorage.setItem(AuthService.ACCESS_TOKEN_KEY, response.accessToken);
    sessionStorage.setItem(AuthService.USER_KEY, JSON.stringify(response.user));
    this._accessToken = response.accessToken;
    this._currentUser.set(response.user);
  }

  private hydrateFromSessionStorage(): void {
    const token = sessionStorage.getItem(AuthService.ACCESS_TOKEN_KEY);
    const userJson = sessionStorage.getItem(AuthService.USER_KEY);

    if (token === null || userJson === null) {
      this.clearSessionStorage();
      return;
    }

    try {
      const user = JSON.parse(userJson) as UserInfo;
      this._accessToken = token;
      this._currentUser.set(user);
    } catch {
      this.clearSessionStorage();
    }
  }

  private clearSessionStorage(): void {
    sessionStorage.removeItem(AuthService.ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(AuthService.USER_KEY);
  }
}
