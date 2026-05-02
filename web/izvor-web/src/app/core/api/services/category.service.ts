import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../../api-base-url.token';
import {
  CategoryResponse,
  CreateCategoryRequest,
  UpdateCategoryRequest
} from '../models/category.model';

@Injectable({ providedIn: 'root' })
export class CategoryService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  listCategories(): Observable<CategoryResponse[]> {
    return this.http.get<CategoryResponse[]>(`${this.apiBaseUrl}/api/categories`);
  }

  getCategory(id: string): Observable<CategoryResponse> {
    return this.http.get<CategoryResponse>(`${this.apiBaseUrl}/api/categories/${id}`);
  }

  createCategory(request: CreateCategoryRequest): Observable<CategoryResponse> {
    return this.http.post<CategoryResponse>(`${this.apiBaseUrl}/api/categories`, request);
  }

  updateCategory(id: string, request: UpdateCategoryRequest): Observable<void> {
    return this.http.put<void>(`${this.apiBaseUrl}/api/categories/${id}`, request);
  }

  deleteCategory(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiBaseUrl}/api/categories/${id}`);
  }
}
