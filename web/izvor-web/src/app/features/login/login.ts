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

import { AuthService } from '../../core/auth/auth.service';
import { TenantContextService } from '../../core/tenant-context';

@Component({
  selector: 'izvor-login',
  imports: [ReactiveFormsModule, Card, InputText, Password, Button, Message],
  template: `
    <div class="login-page">
      <p-card header="Login" styleClass="login-card">
        @if (errorMessage(); as message) {
          <p-message severity="error" [text]="message" styleClass="login-message" />
        }

        <form [formGroup]="form" (ngSubmit)="onSubmit()" class="login-form">
          <div class="login-field">
            <label for="email">Email</label>
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
                  Email is required
                } @else if (form.controls.email.errors?.['email']) {
                  Enter a valid email address
                }
              </small>
            }
          </div>

          <div class="login-field">
            <label for="password">Password</label>
            <p-password
              inputId="password"
              formControlName="password"
              [feedback]="false"
              [toggleMask]="true"
              fluid
            />
            @if (form.controls.password.touched && form.controls.password.invalid) {
              <small class="login-error">Password is required</small>
            }
          </div>

          <p-button
            type="submit"
            label="Sign in"
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
  readonly errorMessage = signal<string | null>(null);

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
      this.errorMessage.set(
        'This URL is not a tenant subdomain. Use https://<your-tenant>.izvor.lvh.me:4200/login'
      );
      return;
    }

    this.loading.set(true);
    this.errorMessage.set(null);

    this.authService
      .login(this.form.getRawValue())
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe({
        next: () => {
          this.router.navigate(['/dashboard']);
        },
        error: (err: unknown) => {
          this.errorMessage.set(this.mapError(err));
        }
      });
  }

  private mapError(err: unknown): string {
    if (err instanceof HttpErrorResponse) {
      if (err.status >= 400 && err.status < 500) {
        return 'Invalid email or password';
      }
    }
    return 'Login service is unavailable. Please try again later.';
  }
}
