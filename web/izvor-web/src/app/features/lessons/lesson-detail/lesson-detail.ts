import { Component, computed, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { DomSanitizer, SafeHtml, Title } from '@angular/platform-browser';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { marked } from 'marked';

import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { Tag } from 'primeng/tag';
import { ConfirmationService, MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

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
  imports: [Button, Message, Tag, RouterLink, TranslateModule],
  template: `
    <div class="page">
      @if (isLoading()) {
        <p>{{ 'lesson.detail.loading' | translate }}</p>
      } @else if (notFound()) {
        <p-message severity="error" [text]="'lesson.detail.notFound' | translate" />
        <p><a [routerLink]="['/courses', courseId()]">{{ 'lesson.detail.backToCourse' | translate }}</a></p>
      } @else if (lesson(); as l) {
        <p class="breadcrumb">
          <a [routerLink]="['/courses', courseId()]">← {{ course()?.title }}</a>
        </p>

        <header class="lesson-header">
          <h1>{{ l.title }}</h1>
          <span class="position">{{ 'lesson.detail.positionFormat' | translate: { position: l.position } }}</span>
          @if (alreadyComplete()) {
            <p-tag [value]="'lesson.detail.completedBadge' | translate" severity="success" />
          }
        </header>

        @if (banner(); as msg) {
          <p-message [severity]="bannerSeverity()" [text]="msg" styleClass="banner" />
        }

        <article>
          @if (l.content) {
            <div class="content" [innerHTML]="renderedContent()"></div>
          } @else {
            <p class="content empty">{{ 'lesson.detail.noContent' | translate }}</p>
          }
        </article>

        <section class="actions">
          @if (canMarkComplete()) {
            <p-button
              [label]="'lesson.detail.markComplete' | translate"
              icon="pi pi-check"
              [loading]="marking()"
              (onClick)="markComplete()"
            />
          }
          @if (canEdit()) {
            <p-button [label]="'lesson.detail.edit' | translate" icon="pi pi-pencil" severity="secondary"
              [routerLink]="['/courses', courseId(), 'lessons', l.id, 'edit']" />
            <p-button [label]="'lesson.detail.delete' | translate" icon="pi pi-trash" severity="danger" [text]="true"
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
      background: var(--p-content-hover-background, #f9fafb);
      padding: 1rem;
      border-radius: 6px;
      margin: 0;
    }
    .content.empty { color: var(--p-text-muted-color, #6b7280); font-style: italic; }
    .content :first-child { margin-top: 0; }
    .content :last-child { margin-bottom: 0; }
    .content pre {
      background: var(--p-content-background, #ffffff);
      padding: 0.75rem;
      border-radius: 4px;
      overflow-x: auto;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    .content code {
      background: var(--p-content-background, #ffffff);
      padding: 0.1rem 0.3rem;
      border-radius: 3px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 0.9em;
    }
    .content pre code { background: transparent; padding: 0; }
    .content blockquote {
      border-left: 3px solid var(--p-content-border-color, #e5e7eb);
      margin: 0.5rem 0;
      padding-left: 1rem;
      color: var(--p-text-muted-color, #6b7280);
    }
    .content ul, .content ol { padding-left: 1.5rem; }
    .content table { border-collapse: collapse; }
    .content th, .content td {
      border: 1px solid var(--p-content-border-color, #e5e7eb);
      padding: 0.25rem 0.5rem;
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
  private readonly sanitizer = inject(DomSanitizer);
  private readonly titleService = inject(Title);
  private readonly translate = inject(TranslateService);

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
    return true;
  });

  // Lesson content is markdown authored by tenant authors (admin/author roles,
  // trusted within a tenant). RLS guarantees content from one tenant never
  // reaches another, so per-tenant XSS surface is bounded by tenant membership.
  readonly renderedContent = computed<SafeHtml>(() => {
    const content = this.lesson()?.content ?? '';
    const html = marked.parse(content, { async: false }) as string;
    return this.sanitizer.bypassSecurityTrustHtml(html);
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
        this.titleService.setTitle(`${lesson.title} · Izvor`);
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
        if (err.status === 404) {
          this.notFound.set(true);
          this.titleService.setTitle('Not Found · Izvor');
        }
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
              this.banner.set(this.translate.instant('lesson.detail.courseCompletedBanner'));
              this.messages.add({ severity: 'success', summary: this.translate.instant('lesson.actions.markComplete.courseCompletedSummary') });
            } else {
              this.messages.add({ severity: 'success', summary: this.translate.instant('lesson.actions.markComplete.successSummary') });
            }
          }
        });
      },
      error: (err: HttpErrorResponse) => {
        this.marking.set(false);
        const body = err.error as ErrorResponse | null | undefined;
        this.bannerSeverity.set('error');
        if (err.status === 409 && body?.message === 'not_enrolled') {
          this.banner.set(this.translate.instant('lesson.detail.notEnrolledError'));
        } else if (err.status === 409 && body?.message === 'enrollment_not_active') {
          this.banner.set(this.translate.instant('lesson.detail.enrollmentInactiveError'));
          this.refreshEnrollment();
        } else {
          this.banner.set(body?.message ?? this.translate.instant('lesson.detail.markFailedError'));
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
      header: this.translate.instant('lesson.actions.delete.confirmHeader'),
      message: this.translate.instant('lesson.actions.delete.confirmMessage', { title: l.title }),
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: this.translate.instant('common.delete'),
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: this.translate.instant('common.cancel'),
      accept: () => this.delete()
    });
  }

  private delete(): void {
    const lid = this.lessonId();
    this.banner.set(null);
    this.lessonService.deleteLesson(lid).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: this.translate.instant('lesson.actions.delete.successSummary') });
        this.router.navigate(['/courses', this.courseId()]);
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        if (err.status === 409 && body?.message === 'lesson_has_progress') {
          this.bannerSeverity.set('error');
          this.banner.set(this.translate.instant('lesson.detail.hasProgressError'));
          return;
        }
        this.messages.add({
          severity: 'error',
          summary: this.translate.instant('lesson.actions.delete.failedSummary'),
          detail: body?.message ?? this.translate.instant('lesson.actions.delete.failedDetail')
        });
      }
    });
  }
}
