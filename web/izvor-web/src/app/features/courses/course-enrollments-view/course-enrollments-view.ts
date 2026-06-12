import { Component, Input, OnChanges, SimpleChanges, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { TableModule } from 'primeng/table';
import { Select } from 'primeng/select';
import { Tag } from 'primeng/tag';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { CourseService } from '../../../core/api/services/course.service';
import { EnrollmentResponse, EnrollmentStatus } from '../../../core/api/models/enrollment.model';
import { LanguageService } from '../../../core/i18n/language.service';
import { EnrollmentStatusLabelPipe } from '../../../core/i18n/enrollment-status-label.pipe';

interface StatusOption {
  label: string;
  value: EnrollmentStatus | 'all';
}

@Component({
  selector: 'izvor-course-enrollments-view',
  imports: [TableModule, Select, Tag, FormsModule, DatePipe, TranslateModule, EnrollmentStatusLabelPipe],
  template: `
    <div class="view">
      <h3>{{ 'course.enrollments.sectionHeader' | translate }}</h3>
      <div class="filter">
        <label>{{ 'course.enrollments.filterStatus' | translate }}</label>
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
        <p>{{ 'course.enrollments.loading' | translate }}</p>
      } @else if (rows().length === 0) {
        <p class="empty">{{ 'course.enrollments.empty' | translate }}</p>
      } @else {
        <p-table [value]="rows()" stripedRows>
          <ng-template pTemplate="header">
            <tr>
              <th>{{ 'course.enrollments.columnUser' | translate }}</th>
              <th>{{ 'course.enrollments.columnStatus' | translate }}</th>
              <th>{{ 'course.enrollments.columnEnrolled' | translate }}</th>
              <th>{{ 'course.enrollments.columnCompleted' | translate }}</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr>
              <td><code>{{ row.userId }}</code></td>
              <td><p-tag [value]="row.status | enrollmentStatusLabel" [severity]="severity(row.status)" /></td>
              <td>{{ row.enrolledAt | date:'medium' }}</td>
              <td>{{ row.finishedAt ? (row.finishedAt | date:'medium') : '—' }}</td>
            </tr>
          </ng-template>
        </p-table>
      }
    </div>
  `,
  styles: [`
    .view { display: flex; flex-direction: column; gap: 0.75rem; }
    .view h3 { margin: 0; }
    .filter { display: flex; flex-direction: column; gap: 0.25rem; max-width: 240px; }
    .filter label { font-size: 0.85rem; color: var(--p-text-muted-color, #6b7280); }
    :host ::ng-deep .filter-select { min-width: 200px; }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    code { font-size: 0.75rem; color: var(--p-text-muted-color, #6b7280); }
  `]
})
export class CourseEnrollmentsView implements OnChanges {
  private readonly courseService = inject(CourseService);
  private readonly translate = inject(TranslateService);
  private readonly languageService = inject(LanguageService);

  @Input({ required: true }) courseId!: string;

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

  readonly isLoading = signal(false);
  readonly rows = signal<EnrollmentResponse[]>([]);

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['courseId']) this.reload();
  }

  reload(): void {
    this.isLoading.set(true);
    this.courseService
      .getCourseEnrollments(
        this.courseId,
        this.statusFilter === 'all' ? undefined : this.statusFilter
      )
      .subscribe({
        next: rows => {
          this.rows.set(rows);
          this.isLoading.set(false);
        },
        error: () => this.isLoading.set(false)
      });
  }

  severity(status: EnrollmentStatus): 'success' | 'info' | 'secondary' {
    if (status === 'completed') return 'success';
    if (status === 'active') return 'info';
    return 'secondary';
  }
}
