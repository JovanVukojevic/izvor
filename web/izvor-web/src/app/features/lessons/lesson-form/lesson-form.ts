import { Component, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Title } from '@angular/platform-browser';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { finalize, forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Textarea } from 'primeng/textarea';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { LessonService } from '../../../core/api/services/lesson.service';
import { CourseService } from '../../../core/api/services/course.service';
import { CourseResponse } from '../../../core/api/models/course.model';
import { LessonResponse } from '../../../core/api/models/lesson.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';
import { AuthService } from '../../../core/auth/auth.service';

@Component({
  selector: 'izvor-lesson-form',
  imports: [ReactiveFormsModule, Card, InputText, Textarea, Button, Message, RouterLink, TranslateModule],
  template: `
    <div class="form-page">
      <p-card [header]="(isEdit() ? 'lesson.form.headerEdit' : 'lesson.form.headerNew') | translate">
        @if (notFound()) {
          <p-message severity="error" [text]="'lesson.form.notFound' | translate" />
          <p><a [routerLink]="['/courses', courseId()]">{{ 'lesson.form.backToCourse' | translate }}</a></p>
        } @else if (isLoading()) {
          <p>{{ 'lesson.form.loading' | translate }}</p>
        } @else {
          @if (errorMessage(); as msg) {
            <p-message severity="error" [text]="msg" styleClass="form-message" />
          }

          <form [formGroup]="form" (ngSubmit)="onSubmit()" class="form">
            <div class="field">
              <label for="title">{{ 'lesson.form.fieldTitle' | translate }}</label>
              <input pInputText id="title" formControlName="title" maxlength="200" fluid />
              @if (form.controls.title.touched && form.controls.title.errors?.['required']) {
                <small class="error">{{ 'lesson.form.errors.titleRequired' | translate }}</small>
              }
            </div>

            @if (isEdit() && lesson(); as l) {
              <div class="field-meta">{{ 'lesson.form.positionLabel' | translate }} {{ l.position }} {{ 'lesson.form.positionHint' | translate }}</div>
            }

            <div class="field">
              <label for="content">{{ 'lesson.form.fieldContent' | translate }}</label>
              <textarea
                pTextarea
                id="content"
                formControlName="content"
                rows="14"
                maxlength="50000"
              ></textarea>
            </div>

            <div class="actions">
              <p-button
                type="submit"
                [label]="(isEdit() ? 'common.save' : 'common.create') | translate"
                [disabled]="form.invalid || saving()"
                [loading]="saving()"
              />
              <p-button
                type="button"
                [label]="'common.cancel' | translate"
                severity="secondary"
                [text]="true"
                (onClick)="cancel()"
              />
            </div>
          </form>
        }
      </p-card>
    </div>
  `,
  styles: [`
    .form-page { max-width: 720px; }
    .form { display: flex; flex-direction: column; gap: 1rem; }
    .field { display: flex; flex-direction: column; gap: 0.375rem; }
    .field label { font-weight: 500; }
    .field-meta { color: var(--p-text-muted-color, #6b7280); font-size: 0.85rem; }
    .actions { display: flex; gap: 0.5rem; }
    .error { color: var(--p-message-error-color, #b91c1c); font-size: 0.85rem; }
    :host ::ng-deep .form-message { width: 100%; margin-bottom: 1rem; }
    textarea { font-family: inherit; }
  `]
})
export class LessonForm {
  private readonly lessonService = inject(LessonService);
  private readonly courseService = inject(CourseService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly auth = inject(AuthService);
  private readonly messages = inject(MessageService);
  private readonly titleService = inject(Title);
  private readonly translate = inject(TranslateService);

  readonly courseId = signal<string>('');
  readonly lessonId = signal<string | null>(null);
  readonly isLoading = signal(false);
  readonly saving = signal(false);
  readonly errorMessage = signal<string | null>(null);
  readonly notFound = signal(false);
  readonly course = signal<CourseResponse | null>(null);
  readonly lesson = signal<LessonResponse | null>(null);

  readonly form = new FormGroup({
    title: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(200)]
    }),
    content: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.maxLength(50000)]
    })
  });

  isEdit(): boolean {
    return this.lessonId() !== null;
  }

  ngOnInit(): void {
    this.courseId.set(this.route.snapshot.paramMap.get('id') ?? '');
    const lessonIdParam = this.route.snapshot.paramMap.get('lessonId');
    if (lessonIdParam !== null) this.lessonId.set(lessonIdParam);
    this.load();
  }

  private load(): void {
    const cid = this.courseId();
    const lid = this.lessonId();

    this.isLoading.set(true);
    forkJoin({
      course: this.courseService.getCourse(cid),
      lesson: lid !== null
        ? this.lessonService.getLesson(lid).pipe(catchError(() => of<LessonResponse | null>(null)))
        : of(null)
    }).subscribe({
      next: ({ course, lesson }) => {
        this.course.set(course);
        if (!this.canEdit(course)) {
          this.router.navigate(['/courses', course.id]);
          return;
        }
        if (lid !== null) {
          if (!lesson) {
            this.notFound.set(true);
            this.isLoading.set(false);
            this.titleService.setTitle('Not Found · Izvor');
            return;
          }
          this.lesson.set(lesson);
          this.form.patchValue({ title: lesson.title, content: lesson.content });
          this.titleService.setTitle(`Edit · ${lesson.title} · Izvor`);
        }
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404) {
          this.notFound.set(true);
          this.titleService.setTitle('Not Found · Izvor');
        } else {
          this.errorMessage.set(this.translate.instant('lesson.form.loadFailed'));
        }
      }
    });
  }

  private canEdit(course: CourseResponse): boolean {
    const u = this.auth.currentUser();
    if (!u) return false;
    return u.role === 'admin' || course.authorId === u.id;
  }

  cancel(): void {
    const lid = this.lessonId();
    if (lid !== null) this.router.navigate(['/courses', this.courseId(), 'lessons', lid]);
    else this.router.navigate(['/courses', this.courseId()]);
  }

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    const raw = this.form.getRawValue();
    const payload = { title: raw.title.trim(), content: raw.content };

    this.saving.set(true);
    this.errorMessage.set(null);

    const lid = this.lessonId();
    if (lid !== null) {
      this.lessonService
        .updateLesson(lid, payload)
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: () => {
            this.messages.add({ severity: 'success', summary: this.translate.instant('lesson.actions.update.successSummary') });
            this.router.navigate(['/courses', this.courseId(), 'lessons', lid]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    } else {
      this.lessonService
        .createLesson(this.courseId(), payload)
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: () => {
            this.messages.add({ severity: 'success', summary: this.translate.instant('lesson.actions.create.successSummary') });
            this.router.navigate(['/courses', this.courseId()]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    }
  }

  private handleError(err: HttpErrorResponse): void {
    const body = err.error as ErrorResponse | null | undefined;
    if (err.status === 404) {
      this.notFound.set(true);
      return;
    }
    this.errorMessage.set(translateApiErrorCode(this.translate, body?.message, 'lesson.form.saveFailed'));
  }
}
