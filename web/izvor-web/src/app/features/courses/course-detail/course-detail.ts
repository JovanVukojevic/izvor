import { Component, computed, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { CdkDrag, CdkDragDrop, CdkDragHandle, CdkDropList, moveItemInArray } from '@angular/cdk/drag-drop';

import { Button } from 'primeng/button';
import { Tag } from 'primeng/tag';
import { Message } from 'primeng/message';
import { ConfirmationService, MessageService } from 'primeng/api';

import { CourseService } from '../../../core/api/services/course.service';
import { LessonService } from '../../../core/api/services/lesson.service';
import { EnrollmentService } from '../../../core/api/services/enrollment.service';
import { CategoryService } from '../../../core/api/services/category.service';
import { CourseResponse, CourseStatus } from '../../../core/api/models/course.model';
import { LessonResponse } from '../../../core/api/models/lesson.model';
import { EnrollmentResponse } from '../../../core/api/models/enrollment.model';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { AuthService } from '../../../core/auth/auth.service';
import { CourseEnrollmentsView } from '../course-enrollments-view/course-enrollments-view';
import { CourseStatsView } from '../course-stats-view/course-stats-view';

@Component({
  selector: 'izvor-course-detail',
  imports: [
    Button,
    Tag,
    Message,
    RouterLink,
    CdkDropList,
    CdkDrag,
    CdkDragHandle,
    CourseEnrollmentsView,
    CourseStatsView
  ],
  template: `
    <div class="page">
      @if (isLoading()) {
        <p>Loading course…</p>
      } @else if (notFound()) {
        <p-message severity="error" text="Course not found" />
        <p><a routerLink="/courses">Back to courses</a></p>
      } @else if (course(); as c) {
        @if (publishError(); as msg) {
          <p-message severity="error" [text]="msg" styleClass="banner" />
        }
        @if (enrollMessage(); as msg) {
          <p-message [severity]="enrollMessageSeverity()" [text]="msg" styleClass="banner" />
        }

        <header class="course-header">
          <div>
            <div class="title-row">
              <h1>{{ c.title }}</h1>
              <p-tag [value]="c.status" [severity]="statusSeverity(c.status)" />
              @if (c.sequential) {
                <p-tag value="sequential" severity="warn" />
              }
            </div>
            <p class="meta">
              Category: {{ categoryName() }} · Author: <code>{{ c.authorId }}</code>
            </p>
          </div>
        </header>

        @if (c.description) {
          <p class="description">{{ c.description }}</p>
        }

        <section class="actions">
          @if (canEdit()) {
            <p-button label="Edit Course" icon="pi pi-pencil" severity="secondary"
              [routerLink]="['/courses', c.id, 'edit']" />
          }
          @if (canPublish()) {
            <p-button label="Publish" icon="pi pi-send" severity="success"
              [loading]="publishing()" (onClick)="publish()" />
          }
          @if (canEdit()) {
            <p-button label="Delete Course" icon="pi pi-trash" severity="danger"
              [text]="true" (onClick)="confirmDelete()" />
          }
          @if (canManageLessons()) {
            <p-button label="Add Lesson" icon="pi pi-plus" severity="secondary"
              [routerLink]="['/courses', c.id, 'lessons', 'new']" />
          }
          @if (canEnroll()) {
            <p-button label="Enroll" icon="pi pi-bookmark"
              [loading]="enrolling()" (onClick)="enroll()" />
          }
          @if (canCancelEnrollment()) {
            <p-button label="Cancel Enrollment" severity="secondary" [text]="true"
              (onClick)="confirmCancelEnrollment()" />
          }
          @if (canEdit()) {
            <p-button label="View Enrollments"
              [severity]="showEnrollmentsView() ? 'primary' : 'secondary'"
              [text]="!showEnrollmentsView()"
              (onClick)="toggleEnrollmentsView()" />
            <p-button label="View Stats"
              [severity]="showStatsView() ? 'primary' : 'secondary'"
              [text]="!showStatsView()"
              (onClick)="toggleStatsView()" />
          }
        </section>

        <section>
          <h2>Lessons</h2>
          @if (lessons().length === 0) {
            <p class="empty">No lessons yet.</p>
          } @else {
            <ol
              class="lessons"
              cdkDropList
              [cdkDropListDisabled]="!canManageLessons() || reordering()"
              (cdkDropListDropped)="onLessonDrop($event)"
            >
              @for (lesson of lessons(); track lesson.id) {
                <li cdkDrag [cdkDragDisabled]="!canManageLessons() || reordering()">
                  @if (canManageLessons()) {
                    <span class="drag-handle" cdkDragHandle title="Drag to reorder">
                      <i class="pi pi-bars"></i>
                    </span>
                  }
                  <a [routerLink]="['/courses', c.id, 'lessons', lesson.id]" class="lesson-link">
                    <span class="lesson-position">{{ lesson.position }}.</span>
                    <span>{{ lesson.title }}</span>
                  </a>
                  @if (canManageLessons()) {
                    <span class="lesson-actions">
                      <p-button icon="pi pi-pencil" size="small" severity="secondary" [text]="true"
                        [routerLink]="['/courses', c.id, 'lessons', lesson.id, 'edit']" />
                      <p-button icon="pi pi-trash" size="small" severity="danger" [text]="true"
                        [disabled]="c.status !== 'draft'"
                        (onClick)="confirmDeleteLesson(lesson)" />
                    </span>
                  }
                </li>
              }
            </ol>
          }
        </section>

        @if (canEdit() && showEnrollmentsView()) {
          <section><izvor-course-enrollments-view [courseId]="c.id" /></section>
        }
        @if (canEdit() && showStatsView()) {
          <section><izvor-course-stats-view [courseId]="c.id" /></section>
        }
      }
    </div>
  `,
  styles: [`
    .page { display: flex; flex-direction: column; gap: 1rem; }
    .course-header { display: flex; justify-content: space-between; align-items: flex-start; }
    .title-row { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
    .title-row h1 { margin: 0; }
    .meta { color: var(--p-text-muted-color, #6b7280); margin: 0.25rem 0 0; }
    .description {
      white-space: pre-wrap;
      background: var(--p-content-hover-background, #f9fafb);
      padding: 1rem;
      border-radius: 6px;
    }
    .actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }
    .lessons { padding-left: 0; list-style: none; margin: 0; display: flex; flex-direction: column; gap: 0.25rem; }
    .lessons li {
      display: flex; align-items: center; justify-content: space-between;
      padding: 0.5rem; border: 1px solid var(--p-content-border-color, #e5e7eb); border-radius: 4px;
    }
    .lesson-link { display: flex; gap: 0.5rem; color: var(--p-text-color, #111827); text-decoration: none; flex: 1; }
    .lesson-link:hover { text-decoration: underline; }
    .lesson-position { color: var(--p-text-muted-color, #6b7280); min-width: 1.5rem; }
    .lesson-actions { display: flex; gap: 0.25rem; }
    .drag-handle {
      display: inline-flex; align-items: center; justify-content: center;
      width: 1.5rem; height: 1.5rem; cursor: grab;
      color: var(--p-text-muted-color, #6b7280);
    }
    .drag-handle:active { cursor: grabbing; }
    .lessons li.cdk-drag-preview {
      box-shadow: 0 5px 5px -3px rgba(0, 0, 0, 0.2),
                  0 8px 10px 1px rgba(0, 0, 0, 0.14),
                  0 3px 14px 2px rgba(0, 0, 0, 0.12);
      background: var(--p-content-background, #ffffff);
    }
    .lessons li.cdk-drag-placeholder { opacity: 0.3; }
    .lessons.cdk-drop-list-dragging li:not(.cdk-drag-placeholder) {
      transition: transform 250ms cubic-bezier(0, 0, 0.2, 1);
    }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    code { font-size: 0.75rem; color: var(--p-text-muted-color, #6b7280); }
    :host ::ng-deep .banner { width: 100%; }
  `]
})
export class CourseDetail {
  private readonly courseService = inject(CourseService);
  private readonly lessonService = inject(LessonService);
  private readonly enrollmentService = inject(EnrollmentService);
  private readonly categoryService = inject(CategoryService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmationService);
  private readonly messages = inject(MessageService);

  readonly courseId = signal<string>('');
  readonly isLoading = signal(true);
  readonly notFound = signal(false);
  readonly course = signal<CourseResponse | null>(null);
  readonly lessons = signal<LessonResponse[]>([]);
  readonly myEnrollment = signal<EnrollmentResponse | null>(null);
  readonly categories = signal<CategoryResponse[]>([]);

  readonly publishing = signal(false);
  readonly enrolling = signal(false);
  readonly reordering = signal(false);
  readonly publishError = signal<string | null>(null);
  readonly enrollMessage = signal<string | null>(null);
  readonly enrollMessageSeverity = signal<'error' | 'warn' | 'info'>('error');

  readonly showEnrollmentsView = signal(false);
  readonly showStatsView = signal(false);

  readonly canEdit = computed(() => {
    const u = this.auth.currentUser();
    const c = this.course();
    if (!u || !c) return false;
    return u.role === 'admin' || c.authorId === u.id;
  });

  readonly canPublish = computed(() => this.canEdit() && this.course()?.status === 'draft');

  readonly canManageLessons = computed(() => this.canEdit() && this.course()?.status !== 'archived');

  readonly canEnroll = computed(() =>
    this.course()?.status === 'published' && this.myEnrollment() === null
  );

  readonly canCancelEnrollment = computed(() => this.myEnrollment()?.status === 'active');

  readonly categoryName = computed(() => {
    const id = this.course()?.categoryId;
    if (!id) return '—';
    return this.categories().find(c => c.id === id)?.name ?? '—';
  });

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.courseId.set(id);
    this.load();
  }

  private load(): void {
    const id = this.courseId();
    const userId = this.auth.currentUser()?.id;
    this.isLoading.set(true);

    forkJoin({
      course: this.courseService.getCourse(id),
      lessons: this.lessonService.listLessonsByCourse(id).pipe(catchError(() => of([] as LessonResponse[]))),
      activeEnrollments: userId
        ? this.enrollmentService.getUserEnrollments(userId, 'active').pipe(catchError(() => of([] as EnrollmentResponse[])))
        : of([] as EnrollmentResponse[]),
      categories: this.categoryService.listCategories().pipe(catchError(() => of([] as CategoryResponse[])))
    }).subscribe({
      next: ({ course, lessons, activeEnrollments, categories }) => {
        this.course.set(course);
        this.lessons.set(lessons);
        this.categories.set(categories);
        this.myEnrollment.set(
          activeEnrollments.find(e => e.courseId === course.id) ?? null
        );
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404) this.notFound.set(true);
      }
    });
  }

  statusSeverity(status: CourseStatus): 'success' | 'info' | 'secondary' {
    if (status === 'published') return 'success';
    if (status === 'draft') return 'info';
    return 'secondary';
  }

  publish(): void {
    const id = this.courseId();
    this.publishError.set(null);
    this.publishing.set(true);
    this.courseService.publishCourse(id).subscribe({
      next: refreshed => {
        this.course.set(refreshed);
        this.publishing.set(false);
        this.messages.add({ severity: 'success', summary: 'Course published' });
      },
      error: (err: HttpErrorResponse) => {
        this.publishing.set(false);
        const body = err.error as ErrorResponse | null | undefined;
        if (err.status === 409 && body?.message === 'course_has_no_lessons') {
          this.publishError.set('Add at least one lesson before publishing.');
        } else {
          this.publishError.set(body?.message ?? 'Could not publish the course.');
        }
      }
    });
  }

  confirmDelete(): void {
    const c = this.course();
    if (!c) return;
    this.confirm.confirm({
      header: 'Delete course',
      message: `Archive "${c.title}"? Published courses become archived; this is a soft delete.`,
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Delete',
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: 'Cancel',
      accept: () => this.delete()
    });
  }

  private delete(): void {
    const id = this.courseId();
    this.courseService.deleteCourse(id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: 'Course deleted' });
        this.router.navigate(['/courses']);
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        this.messages.add({
          severity: 'error',
          summary: 'Delete failed',
          detail: body?.message ?? 'Could not delete the course.'
        });
      }
    });
  }

  enroll(): void {
    const c = this.course();
    const u = this.auth.currentUser();
    if (!c || !u) return;
    this.enrollMessage.set(null);
    this.enrolling.set(true);
    this.enrollmentService.createEnrollment({ courseId: c.id, userId: u.id }).subscribe({
      next: e => {
        this.myEnrollment.set(e);
        this.enrolling.set(false);
        this.messages.add({ severity: 'success', summary: 'Enrolled' });
      },
      error: (err: HttpErrorResponse) => {
        this.enrolling.set(false);
        const body = err.error as ErrorResponse | null | undefined;
        if (err.status === 409 && body?.message === 'enrollment_already_active') {
          this.enrollMessageSeverity.set('warn');
          this.enrollMessage.set('You already have an active enrollment for this course. Refreshing…');
          this.refreshMyEnrollment();
          return;
        }
        this.enrollMessageSeverity.set('error');
        this.enrollMessage.set(body?.message ?? 'Could not enroll.');
      }
    });
  }

  confirmCancelEnrollment(): void {
    const e = this.myEnrollment();
    if (!e) return;
    this.confirm.confirm({
      header: 'Cancel enrollment',
      message: 'Cancel your enrollment? Your progress will be preserved but you will need to re-enroll to continue.',
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Cancel enrollment',
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: 'Keep enrollment',
      accept: () => this.cancelEnrollment(e.id)
    });
  }

  private cancelEnrollment(id: string): void {
    this.enrollmentService.cancelEnrollment(id).subscribe({
      next: () => {
        this.myEnrollment.set(null);
        this.messages.add({ severity: 'success', summary: 'Enrollment cancelled' });
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        if (err.status === 409 && body?.message === 'enrollment_not_active') {
          this.messages.add({ severity: 'info', summary: 'Already inactive' });
          this.refreshMyEnrollment();
          return;
        }
        this.messages.add({
          severity: 'error',
          summary: 'Cancel failed',
          detail: body?.message ?? 'Could not cancel the enrollment.'
        });
      }
    });
  }

  private refreshMyEnrollment(): void {
    const u = this.auth.currentUser();
    const c = this.course();
    if (!u || !c) return;
    this.enrollmentService.getUserEnrollments(u.id, 'active').subscribe({
      next: rows => this.myEnrollment.set(rows.find(e => e.courseId === c.id) ?? null)
    });
  }

  onLessonDrop(event: CdkDragDrop<LessonResponse[]>): void {
    if (event.previousIndex === event.currentIndex) return;

    const original = this.lessons();
    const reordered = [...original];
    moveItemInArray(reordered, event.previousIndex, event.currentIndex);
    this.lessons.set(reordered);

    const moved = original[event.previousIndex];
    const newPosition = event.currentIndex + 1;
    this.reordering.set(true);

    this.lessonService.reorderLesson(moved.id, { position: newPosition }).subscribe({
      next: () => {
        this.lessonService.listLessonsByCourse(this.courseId()).subscribe({
          next: rows => {
            this.lessons.set(rows);
            this.reordering.set(false);
          },
          error: () => this.reordering.set(false)
        });
      },
      error: (err: HttpErrorResponse) => {
        this.lessons.set(original);
        this.reordering.set(false);
        const body = err.error as ErrorResponse | null | undefined;
        this.messages.add({
          severity: 'error',
          summary: 'Reorder failed',
          detail: body?.message ?? 'Could not reorder the lesson.'
        });
      }
    });
  }

  confirmDeleteLesson(lesson: LessonResponse): void {
    this.confirm.confirm({
      header: 'Delete lesson',
      message: `Delete "${lesson.title}"? This cannot be undone.`,
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Delete',
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: 'Cancel',
      accept: () => this.deleteLesson(lesson)
    });
  }

  private deleteLesson(lesson: LessonResponse): void {
    this.lessonService.deleteLesson(lesson.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: 'Lesson deleted' });
        this.lessonService.listLessonsByCourse(this.courseId()).subscribe({
          next: rows => this.lessons.set(rows)
        });
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        this.messages.add({
          severity: 'error',
          summary: 'Delete failed',
          detail: body?.message ?? 'Could not delete the lesson.'
        });
      }
    });
  }

  toggleEnrollmentsView(): void {
    this.showEnrollmentsView.update(v => !v);
  }

  toggleStatsView(): void {
    this.showStatsView.update(v => !v);
  }
}
