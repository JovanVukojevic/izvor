import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { RouterLink } from '@angular/router';
import { FormControl, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';

import { TableModule } from 'primeng/table';
import { Button } from 'primeng/button';
import { Tag } from 'primeng/tag';
import { Select } from 'primeng/select';
import { Dialog } from 'primeng/dialog';
import { Password } from 'primeng/password';
import { ConfirmationService, MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { UserService } from '../../../core/api/services/user.service';
import { UserResponse, ListUsersQuery } from '../../../core/api/models/user.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';
import { RoleLabelPipe } from '../../../core/i18n/role-label.pipe';
import { LanguageService } from '../../../core/i18n/language.service';
import { AuthService } from '../../../core/auth/auth.service';
import { UserRole } from '../../../core/auth/role.utils';

type RoleFilter = UserRole | 'all';
type ActiveFilter = 'all' | 'active' | 'inactive';

interface FilterOption {
  label: string;
  value: string;
}

@Component({
  selector: 'izvor-user-list',
  imports: [
    TableModule,
    Button,
    Tag,
    Select,
    Dialog,
    Password,
    FormsModule,
    ReactiveFormsModule,
    RouterLink,
    DatePipe,
    TranslateModule,
    RoleLabelPipe
  ],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>{{ 'user.list.title' | translate }}</h1>
        <p-button [label]="'user.list.new' | translate" icon="pi pi-plus" routerLink="/users/new" />
      </header>

      <div class="filters">
        <div class="filter">
          <label>{{ 'user.list.filterRole' | translate }}</label>
          <p-select
            [options]="roleOptions()"
            [(ngModel)]="roleFilter"
            (onChange)="load()"
            optionLabel="label"
            optionValue="value"
            styleClass="filter-select"
          />
        </div>
        <div class="filter">
          <label>{{ 'user.list.filterActive' | translate }}</label>
          <p-select
            [options]="activeOptions()"
            [(ngModel)]="activeFilter"
            (onChange)="load()"
            optionLabel="label"
            optionValue="value"
            styleClass="filter-select"
          />
        </div>
      </div>

      @if (isLoading()) {
        <p>{{ 'user.list.loading' | translate }}</p>
      } @else if (users().length === 0) {
        <p class="empty">{{ 'user.list.empty' | translate }}</p>
      } @else {
        <p-table [value]="users()" stripedRows>
          <ng-template pTemplate="header">
            <tr>
              <th>{{ 'user.list.columnEmail' | translate }}</th>
              <th>{{ 'user.list.columnRole' | translate }}</th>
              <th>{{ 'user.list.columnActive' | translate }}</th>
              <th>{{ 'user.list.columnCreated' | translate }}</th>
              <th class="actions-col">{{ 'common.actions' | translate }}</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr>
              <td>{{ row.email }}</td>
              <td>{{ row.role | roleLabel }}</td>
              <td>
                <p-tag
                  [value]="(row.isActive ? 'user.list.activeYes' : 'user.list.activeNo') | translate"
                  [severity]="row.isActive ? 'success' : 'warn'"
                />
              </td>
              <td>{{ row.createdAt | date:'medium' }}</td>
              <td class="actions-col">
                @if (row.isActive) {
                  <p-button
                    icon="pi pi-ban"
                    size="small"
                    severity="danger"
                    [rounded]="true"
                    [text]="true"
                    [disabled]="row.id === currentUserId()"
                    (onClick)="confirmDeactivate(row)"
                  />
                } @else {
                  <p-button
                    icon="pi pi-check"
                    size="small"
                    severity="success"
                    [rounded]="true"
                    [text]="true"
                    (onClick)="confirmActivate(row)"
                  />
                }
                <p-button
                  icon="pi pi-key"
                  size="small"
                  severity="secondary"
                  [rounded]="true"
                  [text]="true"
                  (onClick)="openReset(row)"
                />
              </td>
            </tr>
          </ng-template>
        </p-table>
      }
    </div>

    <p-dialog
      [header]="'user.actions.resetPassword.dialogHeader' | translate"
      [visible]="resetVisible()"
      (visibleChange)="resetVisible.set($event)"
      [modal]="true"
      [style]="{ width: '24rem' }"
    >
      <div class="field">
        <label for="newPassword">{{ 'user.actions.resetPassword.fieldNewPassword' | translate }}</label>
        <p-password
          inputId="newPassword"
          [formControl]="newPassword"
          [feedback]="false"
          [toggleMask]="true"
          fluid
        />
        @if (newPassword.touched && newPassword.invalid) {
          <small class="error">{{ 'user.form.errors.passwordTooShort' | translate }}</small>
        }
      </div>
      <ng-template pTemplate="footer">
        <p-button
          [label]="'common.cancel' | translate"
          severity="secondary"
          [text]="true"
          (onClick)="resetVisible.set(false)"
        />
        <p-button
          [label]="'user.actions.resetPassword.submit' | translate"
          [disabled]="newPassword.invalid || resetting()"
          [loading]="resetting()"
          (onClick)="submitReset()"
        />
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .page { display: flex; flex-direction: column; gap: 1rem; }
    .page-header { display: flex; align-items: center; justify-content: space-between; }
    .page-header h1 { margin: 0; }
    .filters { display: flex; gap: 1rem; flex-wrap: wrap; }
    .filter { display: flex; flex-direction: column; gap: 0.25rem; }
    .filter label { font-size: 0.85rem; color: var(--p-text-muted-color, #6b7280); }
    :host ::ng-deep .filter-select { min-width: 200px; }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    .actions-col { width: 150px; text-align: right; }
    .field { display: flex; flex-direction: column; gap: 0.375rem; }
    .field label { font-weight: 500; }
    .error { color: var(--p-message-error-color, #b91c1c); font-size: 0.85rem; }
  `]
})
export class UserList {
  private readonly service = inject(UserService);
  private readonly confirm = inject(ConfirmationService);
  private readonly messages = inject(MessageService);
  private readonly translate = inject(TranslateService);
  private readonly language = inject(LanguageService);
  private readonly auth = inject(AuthService);

  readonly isLoading = signal(true);
  readonly users = signal<UserResponse[]>([]);

  readonly currentUserId = computed(() => this.auth.currentUser()?.id ?? null);

  roleFilter: RoleFilter = 'all';
  activeFilter: ActiveFilter = 'all';

  readonly roleOptions = computed<FilterOption[]>(() => {
    this.language.currentLocale();
    return [
      { label: this.translate.instant('user.list.filterAll'), value: 'all' },
      { label: this.translate.instant('role.admin'), value: 'admin' },
      { label: this.translate.instant('role.author'), value: 'author' },
      { label: this.translate.instant('role.learner'), value: 'learner' }
    ];
  });

  readonly activeOptions = computed<FilterOption[]>(() => {
    this.language.currentLocale();
    return [
      { label: this.translate.instant('user.list.filterAll'), value: 'all' },
      { label: this.translate.instant('user.list.activeYes'), value: 'active' },
      { label: this.translate.instant('user.list.activeNo'), value: 'inactive' }
    ];
  });

  readonly resetVisible = signal(false);
  readonly resetting = signal(false);
  private readonly resetTarget = signal<UserResponse | null>(null);
  readonly newPassword = new FormControl<string>('', {
    nonNullable: true,
    validators: [Validators.required, Validators.minLength(8)]
  });

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.isLoading.set(true);
    const query: ListUsersQuery = {
      role: this.roleFilter === 'all' ? undefined : this.roleFilter,
      isActive: this.activeFilter === 'all' ? undefined : this.activeFilter === 'active'
    };
    this.service.listUsers(query).subscribe({
      next: rows => {
        this.users.set(rows);
        this.isLoading.set(false);
      },
      error: () => {
        this.isLoading.set(false);
      }
    });
  }

  confirmDeactivate(row: UserResponse): void {
    this.confirm.confirm({
      header: this.translate.instant('user.actions.deactivate.confirmHeader'),
      message: this.translate.instant('user.actions.deactivate.confirmMessage', { email: row.email }),
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: this.translate.instant('common.confirm'),
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: this.translate.instant('common.cancel'),
      accept: () => this.deactivate(row)
    });
  }

  private deactivate(row: UserResponse): void {
    this.service.deactivateUser(row.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: this.translate.instant('user.actions.deactivate.successSummary') });
        this.load();
      },
      error: (err: HttpErrorResponse) => this.actionError(err, 'user.actions.deactivate.failedSummary', 'user.actions.deactivate.failedDetail')
    });
  }

  confirmActivate(row: UserResponse): void {
    this.confirm.confirm({
      header: this.translate.instant('user.actions.activate.confirmHeader'),
      message: this.translate.instant('user.actions.activate.confirmMessage', { email: row.email }),
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: this.translate.instant('common.confirm'),
      rejectLabel: this.translate.instant('common.cancel'),
      accept: () => this.activate(row)
    });
  }

  private activate(row: UserResponse): void {
    this.service.activateUser(row.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: this.translate.instant('user.actions.activate.successSummary') });
        this.load();
      },
      error: (err: HttpErrorResponse) => this.actionError(err, 'user.actions.activate.failedSummary', 'user.actions.activate.failedDetail')
    });
  }

  openReset(row: UserResponse): void {
    this.resetTarget.set(row);
    this.newPassword.reset('');
    this.resetVisible.set(true);
  }

  submitReset(): void {
    if (this.newPassword.invalid) {
      this.newPassword.markAsTouched();
      return;
    }
    const target = this.resetTarget();
    if (target === null) {
      return;
    }
    this.resetting.set(true);
    this.service.resetPassword(target.id, { newPassword: this.newPassword.getRawValue() }).subscribe({
      next: () => {
        this.resetting.set(false);
        this.resetVisible.set(false);
        this.messages.add({ severity: 'success', summary: this.translate.instant('user.actions.resetPassword.successSummary') });
      },
      error: (err: HttpErrorResponse) => {
        this.resetting.set(false);
        this.actionError(err, 'user.actions.resetPassword.failedSummary', 'user.actions.resetPassword.failedDetail');
      }
    });
  }

  private actionError(err: HttpErrorResponse, summaryKey: string, fallbackKey: string): void {
    const body = err.error as ErrorResponse | null | undefined;
    this.messages.add({
      severity: 'error',
      summary: this.translate.instant(summaryKey),
      detail: translateApiErrorCode(this.translate, body?.message, fallbackKey)
    });
  }
}
