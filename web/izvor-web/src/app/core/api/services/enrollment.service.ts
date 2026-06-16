import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../../api-base-url.token';
import {
  EnrollmentResponse,
  EnrollmentStatus,
  EnrollUserRequest,
  LessonCompletionResponse
} from '../models/enrollment.model';

@Injectable({ providedIn: 'root' })
export class EnrollmentService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = inject(API_BASE_URL);

  createEnrollment(request: EnrollUserRequest): Observable<EnrollmentResponse> {
    return this.http.post<EnrollmentResponse>(`${this.apiBaseUrl}/api/enrollments`, request);
  }

  getEnrollment(id: string): Observable<EnrollmentResponse> {
    return this.http.get<EnrollmentResponse>(`${this.apiBaseUrl}/api/enrollments/${id}`);
  }

  cancelEnrollment(id: string): Observable<EnrollmentResponse> {
    return this.http.post<EnrollmentResponse>(`${this.apiBaseUrl}/api/enrollments/${id}/cancel`, null);
  }

  getUserEnrollments(userId: string, status?: EnrollmentStatus): Observable<EnrollmentResponse[]> {
    let httpParams = new HttpParams();
    if (status !== undefined) {
      httpParams = httpParams.set('status', status);
    }
    return this.http.get<EnrollmentResponse[]>(
      `${this.apiBaseUrl}/api/users/${userId}/enrollments`,
      { params: httpParams }
    );
  }

  getEnrollmentCompletions(enrollmentId: string): Observable<LessonCompletionResponse[]> {
    return this.http.get<LessonCompletionResponse[]>(
      `${this.apiBaseUrl}/api/enrollments/${enrollmentId}/completions`
    );
  }
}
