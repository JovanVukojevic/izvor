import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { TableModule } from 'primeng/table';
import { Select } from 'primeng/select';
import { Button } from 'primeng/button';
import { Tag } from 'primeng/tag';
import { ConfirmationService, MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { EnrollmentService } from '../../../core/api/services/enrollment.service';
import { CourseService } from '../../../core/api/services/course.service';
import { EnrollmentResponse, EnrollmentStatus } from '../../../core/api/models/enrollment.model';
import { CourseResponse } from '../../../core/api/models/course.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';
import { AuthService } from '../../../core/auth/auth.service';
import { LanguageService } from '../../../core/i18n/language.service';
import { EnrollmentStatusLabelPipe } from '../../../core/i18n/enrollment-status-label.pipe';
import { TranslitPipe } from '../../../core/i18n/translit.pipe';

interface StatusOption {
  label: string;
  value: EnrollmentStatus | 'all';
}

@Component({
  selector: 'izvor-my-enrollments',
  imports: [TableModule, Select, Button, Tag, FormsModule, DatePipe, TranslateModule, EnrollmentStatusLabelPipe, TranslitPipe],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>{{ 'enrollment.list.title' | translate }}</h1>
      </header>

      <div class="filter">
        <label>{{ 'enrollment.list.filterStatus' | translate }}</label>
        <p-select
          [options]="statusOptions()"
          [(ngModel)]="statusFilter"
          (onChange)="reload()"
          optionLabel="label"
          optionValue="value"
          styleClass="filter-select"
        />
      </div>

      @if (isLoading()) {
        <p>{{ 'enrollment.list.loading' | translate }}</p>
      } @else if (rows().length === 0) {
        <p class="empty">{{ 'enrollment.list.empty' | translate }}</p>
      } @else {
        <p-table [value]="rows()" stripedRows [rowHover]="true">
          <ng-template pTemplate="header">
            <tr>
              <th>{{ 'enrollment.list.columnCourse' | translate }}</th>
              <th>{{ 'enrollment.list.columnStatus' | translate }}</th>
              <th>{{ 'enrollment.list.columnEnrolled' | translate }}</th>
              <th>{{ 'enrollment.list.columnCompleted' | translate }}</th>
              <th class="actions-col">{{ 'common.actions' | translate }}</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr class="row-clickable" (click)="open(row)">
              <td>{{ courseTitle(row.courseId) | translit }}</td>
              <td><p-tag [value]="row.status | enrollmentStatusLabel" [severity]="severity(row.status)" /></td>
              <td>{{ row.enrolledAt | date:'medium' }}</td>
              <td>{{ row.finishedAt ? (row.finishedAt | date:'medium') : '—' }}</td>
              <td class="actions-col" (click)="$event.stopPropagation()">
                @if (row.status === 'active') {
                  <p-button
                    icon="pi pi-times"
                    [label]="'enrollment.cancel.label' | translate"
                    size="small"
                    severity="secondary"
                    [text]="true"
                    (onClick)="confirmCancel(row)"
                  />
                }
              </td>
            </tr>
          </ng-template>
        </p-table>
      }
    </div>
  `,
  styles: [`
    .page { display: flex; flex-direction: column; gap: 1rem; }
    .page-header h1 { margin: 0; }
    .filter { display: flex; flex-direction: column; gap: 0.25rem; max-width: 240px; }
    .filter label { font-size: 0.85rem; color: var(--p-text-muted-color, #6b7280); }
    :host ::ng-deep .filter-select { min-width: 200px; }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    .row-clickable { cursor: pointer; }
    .actions-col { text-align: right; width: 140px; }
  `]
})
export class MyEnrollments {
  private readonly enrollmentService = inject(EnrollmentService);
  private readonly courseService = inject(CourseService);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmationService);
  private readonly messages = inject(MessageService);
  private readonly router = inject(Router);
  private readonly translate = inject(TranslateService);
  private readonly languageService = inject(LanguageService);

  readonly statusOptions = computed<StatusOption[]>(() => {
    this.languageService.currentLocale();
    return [
      { label: this.translate.instant('enrollment.status.active'), value: 'active' },
      { label: this.translate.instant('enrollment.status.completed'), value: 'completed' },
      { label: this.translate.instant('enrollment.status.cancelled'), value: 'cancelled' },
      { label: this.translate.instant('enrollment.status.all'), value: 'all' }
    ];
  });
  statusFilter: EnrollmentStatus | 'all' = 'active';

  readonly isLoading = signal(true);
  readonly rows = signal<EnrollmentResponse[]>([]);
  readonly courses = signal<CourseResponse[]>([]);

  ngOnInit(): void {
    this.isLoading.set(true);
    forkJoin({
      enrollments: this.fetch(),
      courses: this.courseService.listCourses().pipe(catchError(() => of([] as CourseResponse[])))
    }).subscribe({
      next: ({ enrollments, courses }) => {
        this.rows.set(enrollments);
        this.courses.set(courses);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  reload(): void {
    this.isLoading.set(true);
    this.fetch().subscribe({
      next: rows => {
        this.rows.set(rows);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  private fetch() {
    const userId = this.auth.currentUser()?.id;
    if (!userId) return of([] as EnrollmentResponse[]);
    return this.enrollmentService.getUserEnrollments(
      userId,
      this.statusFilter === 'all' ? undefined : this.statusFilter
    );
  }

  open(row: EnrollmentResponse): void {
    this.router.navigate(['/courses', row.courseId]);
  }

  courseTitle(courseId: string): string {
    return this.courses().find(c => c.id === courseId)?.title ?? courseId;
  }

  severity(status: EnrollmentStatus): 'success' | 'info' | 'secondary' {
    if (status === 'completed') return 'success';
    if (status === 'active') return 'info';
    return 'secondary';
  }

  confirmCancel(row: EnrollmentResponse): void {
    this.confirm.confirm({
      header: this.translate.instant('enrollment.cancel.confirmHeader'),
      message: this.translate.instant('enrollment.cancel.confirmMessageMy', { title: this.languageService.transliterateContent(this.courseTitle(row.courseId)) }),
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: this.translate.instant('enrollment.cancel.accept'),
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: this.translate.instant('enrollment.cancel.rejectMy'),
      accept: () => this.cancel(row)
    });
  }

  private cancel(row: EnrollmentResponse): void {
    this.enrollmentService.cancelEnrollment(row.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: this.translate.instant('enrollment.cancel.successSummary') });
        this.reload();
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        if (err.status === 409 && body?.message === 'enrollment_not_active') {
          this.messages.add({ severity: 'info', summary: this.translate.instant('enrollment.cancel.alreadyInactiveSummary') });
          this.reload();
          return;
        }
        this.messages.add({
          severity: 'error',
          summary: this.translate.instant('enrollment.cancel.failedSummary'),
          detail: translateApiErrorCode(this.translate, body?.message, 'enrollment.cancel.failedDetail')
        });
      }
    });
  }
}
