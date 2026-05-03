import { Component, Input, OnChanges, SimpleChanges, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';

import { Card } from 'primeng/card';
import { Message } from 'primeng/message';

import { CourseService } from '../../../core/api/services/course.service';
import { CourseCompletionStatsResponse } from '../../../core/api/models/course.model';

@Component({
  selector: 'izvor-course-stats-view',
  imports: [Card, Message],
  template: `
    <div class="view">
      <h3>Completion Stats</h3>
      @if (isLoading()) {
        <p>Loading stats…</p>
      } @else if (errorMessage(); as msg) {
        <p-message severity="error" [text]="msg" />
      } @else if (stats(); as s) {
        <div class="grid">
          <p-card><strong>{{ s.totalEnrollments }}</strong><span>Total enrollments</span></p-card>
          <p-card><strong>{{ s.activeCount }}</strong><span>Active</span></p-card>
          <p-card><strong>{{ s.completedCount }}</strong><span>Completed</span></p-card>
          <p-card><strong>{{ s.cancelledCount }}</strong><span>Cancelled</span></p-card>
          <p-card><strong>{{ s.averageProgressPct }}%</strong><span>Avg progress (active)</span></p-card>
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
          this.errorMessage.set('You do not have permission to view stats for this course.');
        } else {
          this.errorMessage.set('Could not load completion stats.');
        }
      }
    });
  }
}
