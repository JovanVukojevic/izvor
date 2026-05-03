import { Component, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { finalize } from 'rxjs';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Textarea } from 'primeng/textarea';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { MessageService } from 'primeng/api';

import { CategoryService } from '../../../core/api/services/category.service';
import { ErrorResponse } from '../../../core/api/models/error-response.model';

@Component({
  selector: 'izvor-category-form',
  imports: [ReactiveFormsModule, Card, InputText, Textarea, Button, Message, RouterLink],
  template: `
    <div class="form-page">
      <p-card [header]="isEdit() ? 'Edit Category' : 'New Category'">
        @if (notFound()) {
          <p-message severity="error" text="Category not found" />
          <p><a routerLink="/categories">Back to categories</a></p>
        } @else if (isLoading()) {
          <p>Loading…</p>
        } @else {
          @if (errorMessage(); as msg) {
            <p-message severity="error" [text]="msg" styleClass="form-message" />
          }

          <form [formGroup]="form" (ngSubmit)="onSubmit()" class="form">
            <div class="field">
              <label for="name">Name</label>
              <input pInputText id="name" formControlName="name" maxlength="200" fluid />
              @if (form.controls.name.touched && form.controls.name.invalid) {
                <small class="error">
                  @if (form.controls.name.errors?.['required']) {
                    Name is required
                  } @else if (form.controls.name.errors?.['alreadyExists']) {
                    A category with this name already exists
                  }
                </small>
              }
            </div>

            <div class="field">
              <label for="description">Description</label>
              <textarea
                pTextarea
                id="description"
                formControlName="description"
                rows="4"
                maxlength="1000"
              ></textarea>
            </div>

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
                routerLink="/categories"
              />
            </div>
          </form>
        }
      </p-card>
    </div>
  `,
  styles: [`
    .form-page { max-width: 640px; }
    .form { display: flex; flex-direction: column; gap: 1rem; }
    .field { display: flex; flex-direction: column; gap: 0.375rem; }
    .field label { font-weight: 500; }
    .actions { display: flex; gap: 0.5rem; }
    .error { color: var(--p-message-error-color, #b91c1c); font-size: 0.85rem; }
    :host ::ng-deep .form-message { width: 100%; margin-bottom: 1rem; }
    textarea { font-family: inherit; }
  `]
})
export class CategoryForm {
  private readonly service = inject(CategoryService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly messages = inject(MessageService);

  readonly id = signal<string | null>(null);
  readonly isLoading = signal(false);
  readonly saving = signal(false);
  readonly errorMessage = signal<string | null>(null);
  readonly notFound = signal(false);

  readonly form = new FormGroup({
    name: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(200)]
    }),
    description: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.maxLength(1000)]
    })
  });

  isEdit(): boolean {
    return this.id() !== null;
  }

  ngOnInit(): void {
    const idParam = this.route.snapshot.paramMap.get('id');
    if (idParam !== null) {
      this.id.set(idParam);
      this.loadExisting(idParam);
    }
  }

  private loadExisting(id: string): void {
    this.isLoading.set(true);
    this.service.getCategory(id).subscribe({
      next: c => {
        this.form.patchValue({
          name: c.name,
          description: c.description ?? ''
        });
        this.isLoading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        this.isLoading.set(false);
        if (err.status === 404) {
          this.notFound.set(true);
        } else {
          this.errorMessage.set('Could not load category.');
        }
      }
    });
  }

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const raw = this.form.getRawValue();
    const payload = {
      name: raw.name.trim(),
      description: raw.description.trim().length === 0 ? null : raw.description.trim()
    };

    this.saving.set(true);
    this.errorMessage.set(null);

    const id = this.id();
    const summary = id !== null ? 'Category updated' : 'Category created';
    const onSuccess = () => {
      this.messages.add({ severity: 'success', summary });
      this.router.navigate(['/categories']);
    };
    const onError = (err: HttpErrorResponse) => this.handleError(err);

    if (id !== null) {
      this.service.updateCategory(id, payload)
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({ next: onSuccess, error: onError });
    } else {
      this.service.createCategory(payload)
        .pipe(finalize(() => this.saving.set(false)))
        .subscribe({ next: onSuccess, error: onError });
    }
  }

  private handleError(err: HttpErrorResponse): void {
    const body = err.error as ErrorResponse | null | undefined;
    if (err.status === 409 && (body?.error === 'already_exists' || body?.message?.toLowerCase().includes('already exists'))) {
      this.form.controls.name.setErrors({ alreadyExists: true });
      this.form.controls.name.markAsTouched();
      return;
    }
    if (err.status === 404) {
      this.notFound.set(true);
      return;
    }
    this.errorMessage.set(body?.message ?? 'Could not save category.');
  }
}
