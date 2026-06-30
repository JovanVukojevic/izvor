import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../../api-base-url.token';
import {
  AdminResetPasswordRequest,
  CreateUserRequest,
  ListUsersQuery,
  UserResponse
} from '../models/user.model';

@Injectable({ providedIn: 'root' })
export class UserService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  listUsers(query?: ListUsersQuery): Observable<UserResponse[]> {
    let params = new HttpParams();
    if (query?.role !== undefined) {
      params = params.set('role', query.role);
    }
    if (query?.isActive !== undefined) {
      params = params.set('isActive', query.isActive);
    }
    return this.http.get<UserResponse[]>(`${this.apiBaseUrl}/api/users`, { params });
  }

  getUser(id: string): Observable<UserResponse> {
    return this.http.get<UserResponse>(`${this.apiBaseUrl}/api/users/${id}`);
  }

  createUser(request: CreateUserRequest): Observable<UserResponse> {
    return this.http.post<UserResponse>(`${this.apiBaseUrl}/api/users`, request);
  }

  activateUser(id: string): Observable<void> {
    return this.http.post<void>(`${this.apiBaseUrl}/api/users/${id}/activate`, {});
  }

  deactivateUser(id: string): Observable<void> {
    return this.http.post<void>(`${this.apiBaseUrl}/api/users/${id}/deactivate`, {});
  }

  resetPassword(id: string, request: AdminResetPasswordRequest): Observable<void> {
    return this.http.post<void>(`${this.apiBaseUrl}/api/users/${id}/reset-password`, request);
  }
}
