import { Component, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { finalize, forkJoin, of } from 'rxjs';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Textarea } from 'primeng/textarea';
import { Select } from 'primeng/select';
import { Checkbox } from 'primeng/checkbox';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { MessageService } from 'primeng/api';

import { CourseService } from '../../../core/api/services/course.service';
import { CategoryService } from '../../../core/api/services/category.service';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { CourseResponse } from '../../../core/api/models/course.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { AuthService } from '../../../core/auth/auth.service';

@Component({
  selector: 'izvor-course-form',
  imports: [
    ReactiveFormsModule,
    Card,
    InputText,
    Textarea,
    Select,
    Checkbox,
    Button,
    Message,
    RouterLink
  ],
  template: `
    <div class="form-page">
      <p-card [header]="isEdit() ? 'Edit Course' : 'New Course'">
        @if (notFound()) {
          <p-message severity="error" text="Course not found" />
          <p><a routerLink="/courses">Back to courses</a></p>
        } @else if (isLoading()) {
          <p>Loading…</p>
        } @else {
          @if (errorMessage(); as msg) {
            <p-message severity="error" [text]="msg" styleClass="form-message" />
          }

          <form [formGroup]="form" (ngSubmit)="onSubmit()" class="form">
            <div class="field">
              <label for="title">Title</label>
              <input pInputText id="title" formControlName="title" maxlength="200" fluid />
              @if (form.controls.title.touched && form.controls.title.errors?.['required']) {
                <small class="error">Title is required</small>
              }
            </div>

            <div class="field">
              <label for="description">Description</label>
              <textarea
                pTextarea
                id="description"
                formControlName="description"
                rows="4"
                maxlength="5000"
              ></textarea>
            </div>

            <div class="field">
              <label for="categoryId">Category</label>
              <p-select
                inputId="categoryId"
                [options]="categoryOptions()"
                formControlName="categoryId"
                optionLabel="label"
                optionValue="value"
                placeholder="(no category)"
                [showClear]="true"
                styleClass="form-select"
              />
            </div>

            @if (isEdit()) {
              <div class="field-inline">
                <p-checkbox inputId="sequential" formControlName="sequential" [binary]="true" />
                <label for="sequential">Sequential lessons (learners must complete in order)</label>
              </div>
            }

            <div class="actions">
              <p-button
                type="submit"
                [label]="isEdit() ? 'Save' : 'Create'"
                [disabled]="form.invalid || saving()"
                [loading]="saving()"
              />
              <p-button
                type="button"
                label="Cancel"
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
    categoryId: new FormControl<string | null>(null),
    sequential: new FormControl<boolean>(false, { nonNullable: true })
  });

  isEdit(): boolean {
    return this.id() !== null;
  }

  ngOnInit(): void {
    const idParam = this.route.snapshot.paramMap.get('id');
    if (idParam !== null) {
      this.id.set(idParam);
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
            categoryId: course.categoryId,
            sequential: course.sequential
          });
        }
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404 && id !== null) {
          this.notFound.set(true);
        } else {
          this.errorMessage.set('Could not load form.');
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
          categoryId: raw.categoryId,
          sequential: raw.sequential
        })
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: () => {
            this.messages.add({ severity: 'success', summary: 'Course updated' });
            this.router.navigate(['/courses', id]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    } else {
      this.courseService
        .createCourse({
          title: raw.title.trim(),
          description,
          categoryId: raw.categoryId
        })
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({
          next: created => {
            this.messages.add({ severity: 'success', summary: 'Course created' });
            this.router.navigate(['/courses', created.id]);
          },
          error: (err: HttpErrorResponse) => this.handleError(err)
        });
    }
  }

  private handleError(err: HttpErrorResponse): void {
    const body = err.error as ErrorResponse | null | undefined;
    if (err.status === 404 && body?.message === 'category_not_found') {
      this.errorMessage.set('Selected category no longer exists. Pick a different one.');
      return;
    }
    if (err.status === 404) {
      this.notFound.set(true);
      return;
    }
    this.errorMessage.set(body?.message ?? 'Could not save course.');
  }
}
