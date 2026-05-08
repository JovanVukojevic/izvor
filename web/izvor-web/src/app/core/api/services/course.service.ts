import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../../api-base-url.token';
import {
  CourseCompletionStatsResponse,
  CourseResponse,
  CourseStatus,
  CreateCourseRequest,
  UpdateCourseRequest
} from '../models/course.model';
import { EnrollmentResponse, EnrollmentStatus } from '../models/enrollment.model';

export interface ListCoursesParams {
  categoryId?: string;
  status?: CourseStatus;
  active?: boolean;
}

@Injectable({ providedIn: 'root' })
export class CourseService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  listCourses(params?: ListCoursesParams): Observable<CourseResponse[]> {
    let httpParams = new HttpParams();
    if (params?.categoryId !== undefined) {
      httpParams = httpParams.set('categoryId', params.categoryId);
    }
    if (params?.status !== undefined) {
      httpParams = httpParams.set('status', params.status);
    }
    if (params?.active !== undefined) {
      httpParams = httpParams.set('active', String(params.active));
    }
    return this.http.get<CourseResponse[]>(`${this.apiBaseUrl}/api/courses`, { params: httpParams });
  }

  getCourse(id: string): Observable<CourseResponse> {
    return this.http.get<CourseResponse>(`${this.apiBaseUrl}/api/courses/${id}`);
  }

  createCourse(request: CreateCourseRequest): Observable<CourseResponse> {
    return this.http.post<CourseResponse>(`${this.apiBaseUrl}/api/courses`, request);
  }

  updateCourse(id: string, request: UpdateCourseRequest): Observable<void> {
    return this.http.put<void>(`${this.apiBaseUrl}/api/courses/${id}`, request);
  }

  deleteCourse(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiBaseUrl}/api/courses/${id}`);
  }

  publishCourse(id: string): Observable<CourseResponse> {
    return this.http.post<CourseResponse>(`${this.apiBaseUrl}/api/courses/${id}/publish`, null);
  }

  restoreCourse(id: string): Observable<CourseResponse> {
    return this.http.post<CourseResponse>(`${this.apiBaseUrl}/api/courses/${id}/restore`, null);
  }

  getCourseEnrollments(courseId: string, status?: EnrollmentStatus): Observable<EnrollmentResponse[]> {
    let httpParams = new HttpParams();
    if (status !== undefined) {
      httpParams = httpParams.set('status', status);
    }
    return this.http.get<EnrollmentResponse[]>(
      `${this.apiBaseUrl}/api/courses/${courseId}/enrollments`,
      { params: httpParams }
    );
  }

  getCourseCompletionStats(id: string): Observable<CourseCompletionStatsResponse> {
    return this.http.get<CourseCompletionStatsResponse>(
      `${this.apiBaseUrl}/api/courses/${id}/completion-stats`
    );
  }
}
