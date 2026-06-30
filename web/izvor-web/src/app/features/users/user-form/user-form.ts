import { Component, computed, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { Router, RouterLink } from '@angular/router';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { finalize } from 'rxjs';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Password } from 'primeng/password';
import { Select } from 'primeng/select';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { UserService } from '../../../core/api/services/user.service';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';
import { LanguageService } from '../../../core/i18n/language.service';
import { UserRole } from '../../../core/auth/role.utils';

interface RoleOption {
  label: string;
  value: UserRole;
}

@Component({
  selector: 'izvor-user-form',
  imports: [ReactiveFormsModule, Card, InputText, Password, Select, Button, Message, RouterLink, TranslateModule],
  template: `
    <div class="form-page">
      <p-card [header]="'user.form.headerNew' | translate">
        @if (errorMessage(); as msg) {
          <p-message severity="error" [text]="msg" styleClass="form-message" />
        }

        <form [formGroup]="form" (ngSubmit)="onSubmit()" class="form">
          <div class="field">
            <label for="email">{{ 'user.form.fieldEmail' | translate }}</label>
            <input pInputText id="email" type="email" formControlName="email" maxlength="255" fluid />
            @if (form.controls.email.touched && form.controls.email.invalid) {
              <small class="error">
                @if (form.controls.email.errors?.['required']) {
                  {{ 'user.form.errors.emailRequired' | translate }}
                } @else if (form.controls.email.errors?.['email']) {
                  {{ 'user.form.errors.emailInvalid' | translate }}
                } @else if (form.controls.email.errors?.['alreadyExists']) {
                  {{ 'user.form.errors.alreadyExists' | translate }}
                }
              </small>
            }
          </div>

          <div class="field">
            <label for="password">{{ 'user.form.fieldPassword' | translate }}</label>
            <p-password
              inputId="password"
              formControlName="password"
              [feedback]="false"
              [toggleMask]="true"
              fluid
            />
            @if (form.controls.password.touched && form.controls.password.invalid) {
              <small class="error">
                @if (form.controls.password.errors?.['required']) {
                  {{ 'user.form.errors.passwordRequired' | translate }}
                } @else {
                  {{ 'user.form.errors.passwordTooShort' | translate }}
                }
              </small>
            }
          </div>

          <div class="field">
            <label for="role">{{ 'user.form.fieldRole' | translate }}</label>
            <p-select
              inputId="role"
              [options]="roleOptions()"
              formControlName="role"
              optionLabel="label"
              optionValue="value"
              styleClass="role-select"
            />
          </div>

          <div class="actions">
            <p-button
              type="submit"
              [label]="'common.create' | translate"
              [disabled]="form.invalid || saving()"
              [loading]="saving()"
            />
            <p-button
              type="button"
              [label]="'common.cancel' | translate"
              severity="secondary"
              [text]="true"
              routerLink="/users"
            />
          </div>
        </form>
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
    :host ::ng-deep .role-select { width: 100%; }
  `]
})
export class UserForm {
  private readonly service = inject(UserService);
  private readonly router = inject(Router);
  private readonly messages = inject(MessageService);
  private readonly translate = inject(TranslateService);
  private readonly language = inject(LanguageService);

  readonly saving = signal(false);
  readonly errorMessage = signal<string | null>(null);

  readonly roleOptions = computed<RoleOption[]>(() => {
    this.language.currentLocale();
    return [
      { label: this.translate.instant('role.admin'), value: 'admin' },
      { label: this.translate.instant('role.author'), value: 'author' },
      { label: this.translate.instant('role.learner'), value: 'learner' }
    ];
  });

  readonly form = new FormGroup({
    email: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.email, Validators.maxLength(255)]
    }),
    password: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.minLength(8)]
    }),
    role: new FormControl<UserRole>('learner', {
      nonNullable: true,
      validators: [Validators.required]
    })
  });

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const raw = this.form.getRawValue();
    const payload = {
      email: raw.email.trim(),
      password: raw.password,
      role: raw.role
    };

    this.saving.set(true);
    this.errorMessage.set(null);

    this.service.createUser(payload)
      .pipe(finalize(() => this.saving.set(false)))
      .subscribe({
        next: () => {
          this.messages.add({ severity: 'success', summary: this.translate.instant('user.actions.create.successSummary') });
          this.router.navigate(['/users']);
        },
        error: (err: HttpErrorResponse) => this.handleError(err)
      });
  }

  private handleError(err: HttpErrorResponse): void {
    const body = err.error as ErrorResponse | null | undefined;
    if (err.status === 409 && (body?.error === 'already_exists' || body?.message?.toLowerCase().includes('already exists'))) {
      this.form.controls.email.setErrors({ alreadyExists: true });
      this.form.controls.email.markAsTouched();
      return;
    }
    this.errorMessage.set(translateApiErrorCode(this.translate, body?.message, 'user.form.saveFailed'));
  }
}
