import { Component, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { finalize } from 'rxjs';

import { Card } from 'primeng/card';
import { InputText } from 'primeng/inputtext';
import { Password } from 'primeng/password';
import { Button } from 'primeng/button';
import { Message } from 'primeng/message';
import { TranslateModule } from '@ngx-translate/core';

import { AuthService } from '../../core/auth/auth.service';
import { TenantContextService } from '../../core/tenant-context';
import { LocaleSwitcher } from '../../core/i18n/locale-switcher/locale-switcher';

@Component({
  selector: 'izvor-login',
  imports: [ReactiveFormsModule, Card, InputText, Password, Button, Message, TranslateModule, LocaleSwitcher],
  template: `
    <div class="login-page">
      <p-card [header]="'login.title' | translate" styleClass="login-card">
        <div class="login-locale">
          <izvor-locale-switcher size="small" />
        </div>

        @if (errorKey(); as key) {
          <p-message severity="error" [text]="key | translate" styleClass="login-message" />
        }

        <form [formGroup]="form" (ngSubmit)="onSubmit()" class="login-form">
          <div class="login-field">
            <label for="email">{{ 'login.email.label' | translate }}</label>
            <input
              pInputText
              id="email"
              type="email"
              autocomplete="email"
              formControlName="email"
              fluid
            />
            @if (form.controls.email.touched && form.controls.email.invalid) {
              <small class="login-error">
                @if (form.controls.email.errors?.['required']) {
                  {{ 'login.email.required' | translate }}
                } @else if (form.controls.email.errors?.['email']) {
                  {{ 'login.email.invalid' | translate }}
                }
              </small>
            }
          </div>

          <div class="login-field">
            <label for="password">{{ 'login.password.label' | translate }}</label>
            <p-password
              inputId="password"
              formControlName="password"
              [feedback]="false"
              [toggleMask]="true"
              fluid
            />
            @if (form.controls.password.touched && form.controls.password.invalid) {
              <small class="login-error">{{ 'login.password.required' | translate }}</small>
            }
          </div>

          <p-button
            type="submit"
            [label]="'login.submit' | translate"
            [disabled]="form.invalid || loading()"
            [loading]="loading()"
            styleClass="login-submit"
            fluid
          />
        </form>
      </p-card>
    </div>
  `,
  styles: [`
    .login-page {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 1rem;
    }

    :host ::ng-deep .login-card {
      width: 100%;
      max-width: 400px;
    }

    .login-locale {
      display: flex;
      justify-content: center;
      margin-bottom: 1rem;
    }

    :host ::ng-deep .login-locale .p-selectbutton {
      flex-wrap: wrap;
    }

    .login-form {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .login-field {
      display: flex;
      flex-direction: column;
      gap: 0.375rem;
    }

    .login-field label {
      font-weight: 500;
    }

    .login-error {
      color: var(--p-message-error-color, #b91c1c);
      font-size: 0.85rem;
    }

    :host ::ng-deep .login-message {
      width: 100%;
      margin-bottom: 1rem;
    }

    :host ::ng-deep p-password,
    :host ::ng-deep p-password .p-password {
      width: 100%;
    }
  `]
})
export class Login {
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);
  private readonly tenantContext = inject(TenantContextService);

  readonly loading = signal(false);
  readonly errorKey = signal<string | null>(null);

  readonly form = new FormGroup({
    email: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required, Validators.email]
    }),
    password: new FormControl<string>('', {
      nonNullable: true,
      validators: [Validators.required]
    })
  });

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    if (!this.tenantContext.isTenantContext) {
      this.errorKey.set('login.errors.tenantContext');
      return;
    }

    this.loading.set(true);
    this.errorKey.set(null);

    this.authService
      .login(this.form.getRawValue())
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe({
        next: () => {
          this.router.navigate(['/dashboard']);
        },
        error: (err: unknown) => {
          this.errorKey.set(this.mapErrorKey(err));
        }
      });
  }

  private mapErrorKey(err: unknown): string {
    if (err instanceof HttpErrorResponse && err.status >= 400 && err.status < 500) {
      return 'login.errors.invalidCredentials';
    }
    return 'login.errors.unavailable';
  }
}
