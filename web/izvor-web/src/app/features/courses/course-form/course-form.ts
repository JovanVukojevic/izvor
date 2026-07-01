import { Component, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Title } from '@angular/platform-browser';
import { AbstractControl, FormArray, FormControl, FormGroup, ReactiveFormsModule, ValidationErrors, Validators } from '@angular/forms';
import { CdkDrag, CdkDragDrop, CdkDragHandle, CdkDropList, moveItemInArray } from '@angular/cdk/drag-drop';
import { finalize, forkJoin, of } from 'rxjs';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Textarea } from 'primeng/textarea';
import { MultiSelect } from 'primeng/multiselect';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { CourseService } from '../../../core/api/services/course.service';
import { CategoryService } from '../../../core/api/services/category.service';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { CourseResponse } from '../../../core/api/models/course.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';
import { AuthService } from '../../../core/auth/auth.service';

type LessonGroup = FormGroup<{
  title: FormControl<string>;
  content: FormControl<string>;
}>;

// mirrors impl.lessons.title CHECK length(trim(title)) BETWEEN 1 AND 300
const lessonTitleValidator = (c: AbstractControl): ValidationErrors | null => {
  const value = (c.value ?? '').trim();
  if (value.length === 0) return { required: true };
  if (value.length > 300) return { maxlength: true };
  return null;
};

const atLeastOneLesson = (c: AbstractControl): ValidationErrors | null =>
  (c as FormArray).length >= 1 ? null : { atLeastOneLesson: true };

@Component({
  selector: 'izvor-course-form',
  imports: [
    ReactiveFormsModule,
    CdkDropList,
    CdkDrag,
    CdkDragHandle,
    Card,
    InputText,
    Textarea,
    MultiSelect,
    Button,
    Message,
    RouterLink,
    TranslateModule
  ],
  template: `
    <div class="form-page">
      <p-card [header]="(isEdit() ? 'course.form.headerEdit' : 'course.form.headerNew') | translate">
        @if (notFound()) {
          <p-message severity="error" [text]="'course.form.notFound' | translate" />
          <p><a routerLink="/courses">{{ 'course.form.backToCourses' | translate }}</a></p>
        } @else if (isLoading()) {
          <p>{{ 'course.form.loading' | translate }}</p>
        } @else {
          @if (errorMessage(); as msg) {
            <p-message severity="error" [text]="msg" styleClass="form-message" />
          }

          <form [formGroup]="form" (ngSubmit)="onSubmit()" class="form">
            <div class="field">
              <label for="title">{{ 'course.form.fieldTitle' | translate }}</label>
              <input pInputText id="title" formControlName="title" maxlength="200" fluid />
              @if (form.controls.title.touched && form.controls.title.errors?.['required']) {
                <small class="error">{{ 'course.form.errors.titleRequired' | translate }}</small>
              }
            </div>

            <div class="field">
              <label for="description">{{ 'course.form.fieldDescription' | translate }}</label>
              <textarea
                pTextarea
                id="description"
                formControlName="description"
                rows="4"
                maxlength="5000"
              ></textarea>
            </div>

            <div class="field">
              <label for="categoryIds">{{ 'course.form.fieldCategory' | translate }}</label>
              <p-multiselect
                inputId="categoryIds"
                [options]="categoryOptions()"
                formControlName="categoryIds"
                optionLabel="label"
                optionValue="value"
                [placeholder]="'course.form.selectCategoryPlaceholder' | translate"
                display="chip"
                styleClass="form-select"
              />
              @if (form.controls.categoryIds.touched && form.controls.categoryIds.errors?.['required']) {
                <small class="error">{{ 'course.form.errors.categoryRequired' | translate }}</small>
              }
            </div>

            @if (!isEdit()) {
              <div class="lessons-block">
                <div class="lessons-header">{{ 'course.form.lessonsHeader' | translate }}</div>
                <p class="lessons-hint">{{ 'course.form.dragHint' | translate }}</p>

                <div formArrayName="lessons" cdkDropList (cdkDropListDropped)="onLessonDrop($event)">
                  @for (row of lessons.controls; track row; let i = $index) {
                    <div class="lesson-row" cdkDrag [formGroupName]="i">
                      <span class="drag-handle" cdkDragHandle [title]="'course.form.dragHint' | translate">
                        <i class="pi pi-bars"></i>
                      </span>
                      <div class="lesson-fields">
                        <input
                          pInputText
                          formControlName="title"
                          maxlength="300"
                          [placeholder]="'course.form.fieldLessonTitle' | translate"
                          fluid
                        />
                        @if (row.get('title')?.touched && row.get('title')?.errors?.['required']) {
                          <small class="error">{{ 'course.form.errors.lessonTitleRequired' | translate }}</small>
                        } @else if (row.get('title')?.touched && row.get('title')?.errors?.['maxlength']) {
                          <small class="error">{{ 'course.form.errors.lessonTitleLength' | translate }}</small>
                        }
                        <textarea
                          pTextarea
                          formControlName="content"
                          rows="4"
                          maxlength="20000"
                          [placeholder]="'course.form.fieldLessonContent' | translate"
                        ></textarea>
                      </div>
                      <p-button
                        icon="pi pi-trash"
                        severity="danger"
                        [text]="true"
                        [attr.aria-label]="'course.form.removeLesson' | translate"
                        (onClick)="removeLesson(i)"
                      />
                    </div>
                  }
                </div>

                @if (lessons.length === 0) {
                  <small class="error">{{ 'course.form.errors.atLeastOneLesson' | translate }}</small>
                }

                <p-button
                  type="button"
                  icon="pi pi-plus"
                  severity="secondary"
                  [text]="true"
                  [label]="'course.form.addLesson' | translate"
                  (onClick)="addLesson()"
                />
              </div>
            }

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
    .field-inline { display: flex; align-items: center; gap: 0.5rem; }
    .lessons-block {
      display: flex;
      flex-direction: column;
      gap: 1rem;
      padding: 1rem;
      border: 1px solid var(--p-content-border-color, #e5e7eb);
      border-radius: 6px;
      background: var(--p-content-hover-background, #f9fafb);
    }
    .lessons-header { font-weight: 600; }
    .lessons-hint {
      margin: 0;
      color: var(--p-text-muted-color, #6b7280);
      font-size: 0.9rem;
    }
    .lesson-row {
      display: flex;
      align-items: flex-start;
      gap: 0.5rem;
      padding: 0.75rem;
      margin-bottom: 0.5rem;
      border: 1px solid var(--p-content-border-color, #e5e7eb);
      border-radius: 6px;
      background: var(--p-content-background, #ffffff);
    }
    .lesson-fields {
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: 0.375rem;
    }
    .drag-handle {
      cursor: grab;
      padding-top: 0.5rem;
      color: var(--p-text-muted-color, #6b7280);
    }
    .cdk-drag-preview { box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15); }
    .cdk-drag-placeholder { opacity: 0.4; }
    .actions { display: flex; gap: 0.5rem; }
    .error { color: var(--p-message-error-color, #b91c1c); font-size: 0.85rem; }
    :host ::ng-deep .form-message { width: 100%; margin-bottom: 1rem; }
    :host ::ng-deep .form-select { width: 100%; }
    textarea { font-family: inherit; }
  `]
})
export class CourseForm {
  private readonly courseService = inject(CourseService);
  private readonly categoryService = inject(CategoryService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly auth = inject(AuthService);
  private readonly messages = inject(MessageService);
  private readonly titleService = inject(Title);
  private readonly translate = inject(TranslateService);

  readonly id = signal<string | null>(null);
  readonly isLoading = signal(false);
  readonly saving = signal(false);
  readonly errorMessage = signal<string | null>(null);
  readonly notFound = signal(false);
  readonly categories = signal<CategoryResponse[]>([]);

  readonly categoryOptions = () =>
    this.categories().map(c => ({ label: c.name, value: c.id }));

  readonly form = new FormGroup({
    title: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(200)]
    }),
    description: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.maxLength(5000)]
    }),
    // Validators.required on an array returns valid for []; the inline validator
    // mirrors the backend NotEmpty() contract by raising 'required' when empty.
    categoryIds: new FormControl<string[]>([], {
      nonNullable: true,
      validators: [
        (c: AbstractControl): ValidationErrors | null =>
          Array.isArray(c.value) && c.value.length > 0 ? null : { required: true }
      ]
    }),
    lessons: new FormArray<LessonGroup>([], atLeastOneLesson)
  });

  get lessons(): FormArray<LessonGroup> {
    return this.form.controls.lessons;
  }

  private newLessonGroup(): LessonGroup {
    return new FormGroup({
      title: new FormControl<string>('', {
        nonNullable: true,
        validators: [lessonTitleValidator]
      }),
      content: new FormControl<string>('', {
        nonNullable: true,
        validators: [Validators.maxLength(20000)]
      })
    });
  }

  addLesson(): void {
    this.lessons.push(this.newLessonGroup());
  }

  removeLesson(index: number): void {
    this.lessons.removeAt(index);
  }

  onLessonDrop(event: CdkDragDrop<LessonGroup[]>): void {
    if (event.previousIndex === event.currentIndex) return;
    moveItemInArray(this.lessons.controls, event.previousIndex, event.currentIndex);
    this.lessons.updateValueAndValidity();
  }

  isEdit(): boolean {
    return this.id() !== null;
  }

  ngOnInit(): void {
    const idParam = this.route.snapshot.paramMap.get('id');
    if (idParam !== null) {
      this.id.set(idParam);
      // The lessons section is create-only; in edit mode it is not in the template,
      // so disabling it excludes the FormArray from form-wide validity.
      this.form.controls.lessons.disable({ emitEvent: false });
    } else {
      this.addLesson();
    }
    this.load();
  }

  private load(): void {
    this.isLoading.set(true);
    const id = this.id();
    forkJoin({
      categories: this.categoryService.listCategories(),
      course: id !== null ? this.courseService.getCourse(id) : of(null)
    }).subscribe({
      next: ({ categories, course }) => {
        this.categories.set(categories);
        if (course) {
          if (!this.canEdit(course)) {
            this.router.navigate(['/courses', course.id]);
            return;
          }
          this.form.patchValue({
            title: course.title,
            description: course.description ?? '',
            categoryIds: course.categoryIds ?? []
          });
          this.titleService.setTitle(`Edit · ${course.title} · Izvor`);
        }
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404 && id !== null) {
          this.notFound.set(true);
          this.titleService.setTitle('Not Found · Izvor');
        } else {
          this.errorMessage.set(this.translate.instant('course.form.loadFailed'));
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
    const id = this.id();
    if (id !== null) this.router.navigate(['/courses', id]);
    else this.router.navigate(['/courses']);
  }

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const raw = this.form.getRawValue();
    const description = raw.description.trim().length === 0 ? null : raw.description.trim();
    this.saving.set(true);
    this.errorMessage.set(null);

    const id = this.id();
    if (id !== null) {
      this.courseService
        .updateCourse(id, {
          title: raw.title.trim(),
          description,
          categoryIds: raw.categoryIds
        })
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: () => {
            this.messages.add({ severity: 'success', summary: this.translate.instant('course.actions.update.successSummary') });
            this.router.navigate(['/courses', id]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    } else {
      this.courseService
        .createCourse({
          title: raw.title.trim(),
          description,
          categoryIds: raw.categoryIds,
          lessons: raw.lessons.map(l => ({ title: l.title.trim(), content: l.content }))
        })
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: created => {
            this.messages.add({ severity: 'success', summary: this.translate.instant('course.actions.create.successSummary') });
            this.router.navigate(['/courses', created.id]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    }
  }

  private handleError(err: HttpErrorResponse): void {
    const body = err.error as ErrorResponse | null | undefined;
    if (err.status === 400 && body?.message === 'category_required') {
      this.form.controls.categoryIds.setErrors({ required: true });
      this.form.controls.categoryIds.markAsTouched();
      return;
    }
    if (err.status === 404 && body?.message === 'category_not_found') {
      this.errorMessage.set(this.translate.instant('course.form.categoryGoneError'));
      return;
    }
    if (err.status === 404) {
      this.notFound.set(true);
      return;
    }
    this.errorMessage.set(translateApiErrorCode(this.translate, body?.message, 'course.form.saveFailed'));
  }
}
