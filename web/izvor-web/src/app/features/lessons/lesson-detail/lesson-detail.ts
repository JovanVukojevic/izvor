import { Component, computed, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { Tag } from 'primeng/tag';
import { ConfirmationService, MessageService } from 'primeng/api';

import { LessonService } from '../../../core/api/services/lesson.service';
import { CourseService } from '../../../core/api/services/course.service';
import { EnrollmentService } from '../../../core/api/services/enrollment.service';
import { LessonResponse } from '../../../core/api/models/lesson.model';
import { CourseResponse } from '../../../core/api/models/course.model';
import { EnrollmentResponse, LessonProgressResponse } from '../../../core/api/models/enrollment.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { AuthService } from '../../../core/auth/auth.service';

@Component({
  selector: 'izvor-lesson-detail',
  imports: [Button, Message, Tag, RouterLink],
  template: `
    <div class="page">
      @if (isLoading()) {
        <p>Loading lesson…</p>
      } @else if (notFound()) {
        <p-message severity="error" text="Lesson not found" />
        <p><a [routerLink]="['/courses', courseId()]">Back to course</a></p>
      } @else if (lesson(); as l) {
        <p class="breadcrumb">
          <a [routerLink]="['/courses', courseId()]">← {{ course()?.title ?? 'Course' }}</a>
        </p>

        <header class="lesson-header">
          <h1>{{ l.title }}</h1>
          <span class="position">Lesson {{ l.position }}</span>
          @if (alreadyComplete()) {
            <p-tag value="completed" severity="success" />
          }
        </header>

        @if (banner(); as msg) {
          <p-message [severity]="bannerSeverity()" [text]="msg" styleClass="banner" />
        }

        <article>
          <pre class="content">{{ l.content || '(no content)' }}</pre>
        </article>

        <section class="actions">
          @if (canMarkComplete()) {
            <p-button
              label="Mark Complete"
              icon="pi pi-check"
              [loading]="marking()"
              (onClick)="markComplete()"
            />
          }
          @if (canEdit()) {
            <p-button label="Edit Lesson" icon="pi pi-pencil" severity="secondary"
              [routerLink]="['/courses', courseId(), 'lessons', l.id, 'edit']" />
            <p-button label="Delete Lesson" icon="pi pi-trash" severity="danger" [text]="true"
              [disabled]="course()?.status !== 'draft'"
              (onClick)="confirmDelete()" />
          }
        </section>
      }
    </div>
  `,
  styles: [`
    .page { display: flex; flex-direction: column; gap: 1rem; }
    .breadcrumb { margin: 0; }
    .breadcrumb a { color: var(--p-text-muted-color, #6b7280); text-decoration: none; }
    .breadcrumb a:hover { text-decoration: underline; }
    .lesson-header { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
    .lesson-header h1 { margin: 0; }
    .position { color: var(--p-text-muted-color, #6b7280); }
    .content {
      white-space: pre-wrap;
      font-family: inherit;
      background: var(--p-content-hover-background, #f9fafb);
      padding: 1rem;
      border-radius: 6px;
      margin: 0;
    }
    .actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }
    :host ::ng-deep .banner { width: 100%; }
  `]
})
export class LessonDetail {
  private readonly lessonService = inject(LessonService);
  private readonly courseService = inject(CourseService);
  private readonly enrollmentService = inject(EnrollmentService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmationService);
  private readonly messages = inject(MessageService);

  readonly courseId = signal<string>('');
  readonly lessonId = signal<string>('');
  readonly isLoading = signal(true);
  readonly notFound = signal(false);
  readonly lesson = signal<LessonResponse | null>(null);
  readonly course = signal<CourseResponse | null>(null);
  readonly myEnrollment = signal<EnrollmentResponse | null>(null);
  readonly progress = signal<LessonProgressResponse[]>([]);

  readonly marking = signal(false);
  readonly banner = signal<string | null>(null);
  readonly bannerSeverity = signal<'error' | 'warn' | 'info' | 'success'>('info');

  readonly canEdit = computed(() => {
    const u = this.auth.currentUser();
    const c = this.course();
    if (!u || !c) return false;
    return u.role === 'admin' || c.authorId === u.id;
  });

  readonly alreadyComplete = computed(() => {
    const lid = this.lesson()?.id;
    if (!lid) return false;
    return this.progress().some(p => p.lessonId === lid);
  });

  readonly canMarkComplete = computed(() => {
    const e = this.myEnrollment();
    if (!e || e.status !== 'active') return false;
    if (this.alreadyComplete()) return false;
    return this.course()?.status === 'published';
  });

  ngOnInit(): void {
    this.courseId.set(this.route.snapshot.paramMap.get('id') ?? '');
    this.lessonId.set(this.route.snapshot.paramMap.get('lessonId') ?? '');
    this.load();
  }

  private load(): void {
    const userId = this.auth.currentUser()?.id;
    this.isLoading.set(true);

    forkJoin({
      lesson: this.lessonService.getLesson(this.lessonId()),
      course: this.courseService.getCourse(this.courseId()),
      activeEnrollments: userId
        ? this.enrollmentService.getUserEnrollments(userId, 'active').pipe(catchError(() => of([] as EnrollmentResponse[])))
        : of([] as EnrollmentResponse[])
    }).subscribe({
      next: ({ lesson, course, activeEnrollments }) => {
        this.lesson.set(lesson);
        this.course.set(course);
        const myE = activeEnrollments.find(e => e.courseId === course.id) ?? null;
        this.myEnrollment.set(myE);
        if (myE) {
          this.enrollmentService.getEnrollmentProgress(myE.id).subscribe({
            next: rows => {
              this.progress.set(rows);
              this.isLoading.set(false);
            },
            error: () => this.isLoading.set(false)
          });
        } else {
          this.isLoading.set(false);
        }
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404) this.notFound.set(true);
      }
    });
  }

  markComplete(): void {
    const lid = this.lessonId();
    const e = this.myEnrollment();
    if (!e) return;
    this.banner.set(null);
    this.marking.set(true);
    this.lessonService.markLessonComplete(lid).subscribe({
      next: () => {
        this.marking.set(false);
        this.enrollmentService.getEnrollment(e.id).subscribe({
          next: refreshed => {
            this.myEnrollment.set(refreshed);
            this.enrollmentService.getEnrollmentProgress(e.id).subscribe({
              next: rows => this.progress.set(rows)
            });
            if (refreshed.status === 'completed') {
              this.bannerSeverity.set('success');
              this.banner.set('Course completed! All lessons marked complete.');
              this.messages.add({ severity: 'success', summary: 'Course completed' });
            } else {
              this.messages.add({ severity: 'success', summary: 'Lesson marked complete' });
            }
          }
        });
      },
      error: (err: HttpErrorResponse) => {
        this.marking.set(false);
        const body = err.error as ErrorResponse | null | undefined;
        this.bannerSeverity.set('error');
        if (err.status === 409 && body?.message === 'prerequisite_lesson_incomplete') {
          this.banner.set('Complete the previous lessons in order before this one.');
        } else if (err.status === 409 && body?.message === 'not_enrolled') {
          this.banner.set('You must enroll in this course before marking lessons complete.');
        } else if (err.status === 409 && body?.message === 'enrollment_not_active') {
          this.banner.set('Your enrollment is no longer active.');
          this.refreshEnrollment();
        } else {
          this.banner.set(body?.message ?? 'Could not mark this lesson complete.');
        }
      }
    });
  }

  private refreshEnrollment(): void {
    const e = this.myEnrollment();
    if (!e) return;
    this.enrollmentService.getEnrollment(e.id).subscribe({
      next: refreshed => this.myEnrollment.set(refreshed)
    });
  }

  confirmDelete(): void {
    const l = this.lesson();
    if (!l) return;
    this.confirm.confirm({
      header: 'Delete lesson',
      message: `Delete "${l.title}"? This cannot be undone.`,
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Delete',
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: 'Cancel',
      accept: () => this.delete()
    });
  }

  private delete(): void {
    const lid = this.lessonId();
    this.lessonService.deleteLesson(lid).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: 'Lesson deleted' });
        this.router.navigate(['/courses', this.courseId()]);
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
}
