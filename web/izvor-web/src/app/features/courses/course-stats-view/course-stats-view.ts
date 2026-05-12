import { Component, Input, OnChanges, SimpleChanges, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';

import { Card } from 'primeng/card';
import { Message } from 'primeng/message';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { CourseService } from '../../../core/api/services/course.service';
import { CourseCompletionStatsResponse } from '../../../core/api/models/course.model';

@Component({
  selector: 'izvor-course-stats-view',
  imports: [Card, Message, TranslateModule],
  template: `
    <div class="view">
      <h3>{{ 'course.stats.sectionHeader' | translate }}</h3>
      @if (isLoading()) {
        <p>{{ 'course.stats.loading' | translate }}</p>
      } @else if (errorMessage(); as msg) {
        <p-message severity="error" [text]="msg" />
      } @else if (stats(); as s) {
        <div class="grid">
          <p-card><strong>{{ s.totalEnrollments }}</strong><span>{{ 'course.stats.totalEnrollments' | translate }}</span></p-card>
          <p-card><strong>{{ s.activeCount }}</strong><span>{{ 'course.stats.active' | translate }}</span></p-card>
          <p-card><strong>{{ s.completedCount }}</strong><span>{{ 'course.stats.completed' | translate }}</span></p-card>
          <p-card><strong>{{ s.cancelledCount }}</strong><span>{{ 'course.stats.cancelled' | translate }}</span></p-card>
          <p-card><strong>{{ s.averageProgressPct }}%</strong><span>{{ 'course.stats.avgProgress' | translate }}</span></p-card>
        </div>
      }
    </div>
  `,
  styles: [`
    .view { display: flex; flex-direction: column; gap: 0.75rem; }
    .view h3 { margin: 0; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 0.75rem;
    }
    .grid :host ::ng-deep .p-card-body,
    .grid p-card {
      text-align: center;
    }
    .grid strong { display: block; font-size: 1.75rem; }
    .grid span { color: var(--p-text-muted-color, #6b7280); font-size: 0.85rem; }
  `]
})
export class CourseStatsView implements OnChanges {
  private readonly courseService = inject(CourseService);
  private readonly translate = inject(TranslateService);

  @Input({ required: true }) courseId!: string;

  readonly isLoading = signal(false);
  readonly stats = signal<CourseCompletionStatsResponse | null>(null);
  readonly errorMessage = signal<string | null>(null);

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['courseId']) this.reload();
  }

  reload(): void {
    this.isLoading.set(true);
    this.errorMessage.set(null);
    this.courseService.getCourseCompletionStats(this.courseId).subscribe({
      next: s => {
        this.stats.set(s);
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 403) {
          this.errorMessage.set(this.translate.instant('course.stats.forbiddenError'));
        } else {
          this.errorMessage.set(this.translate.instant('course.stats.loadFailedError'));
        }
      }
    });
  }
}
