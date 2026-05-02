import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../../api-base-url.token';
import {
  CreateLessonRequest,
  LessonResponse,
  ReorderLessonRequest,
  UpdateLessonRequest
} from '../models/lesson.model';

@Injectable({ providedIn: 'root' })
export class LessonService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  listLessonsByCourse(courseId: string): Observable<LessonResponse[]> {
    return this.http.get<LessonResponse[]>(
      `${this.apiBaseUrl}/api/courses/${courseId}/lessons`
    );
  }

  getLesson(id: string): Observable<LessonResponse> {
    return this.http.get<LessonResponse>(`${this.apiBaseUrl}/api/lessons/${id}`);
  }

  createLesson(courseId: string, request: CreateLessonRequest): Observable<LessonResponse> {
    return this.http.post<LessonResponse>(
      `${this.apiBaseUrl}/api/courses/${courseId}/lessons`,
      request
    );
  }

  updateLesson(id: string, request: UpdateLessonRequest): Observable<void> {
    return this.http.put<void>(`${this.apiBaseUrl}/api/lessons/${id}`, request);
  }

  deleteLesson(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiBaseUrl}/api/lessons/${id}`);
  }

  reorderLesson(id: string, request: ReorderLessonRequest): Observable<LessonResponse> {
    return this.http.post<LessonResponse>(
      `${this.apiBaseUrl}/api/lessons/${id}/reorder`,
      request
    );
  }

  markLessonComplete(id: string): Observable<void> {
    return this.http.post<void>(`${this.apiBaseUrl}/api/lessons/${id}/complete`, null);
  }
}
