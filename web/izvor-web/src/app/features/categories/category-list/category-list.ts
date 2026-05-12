import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { RouterLink } from '@angular/router';

import { TableModule } from 'primeng/table';
import { Button } from 'primeng/button';
import { ConfirmationService, MessageService } from 'primeng/api';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { CategoryService } from '../../../core/api/services/category.service';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';
import { translateApiErrorCode } from '../../../core/api/translate-api-error';

@Component({
  selector: 'izvor-category-list',
  imports: [TableModule, Button, RouterLink, DatePipe, TranslateModule],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>{{ 'category.list.title' | translate }}</h1>
        <p-button [label]="'category.list.new' | translate" icon="pi pi-plus" routerLink="/categories/new" />
      </header>

      @if (isLoading()) {
        <p>{{ 'category.list.loading' | translate }}</p>
      } @else if (categories().length === 0) {
        <p class="empty">{{ 'category.list.empty' | translate }}</p>
      } @else {
        <p-table [value]="categories()" stripedRows>
          <ng-template pTemplate="header">
            <tr>
              <th>{{ 'category.list.columnName' | translate }}</th>
              <th>{{ 'category.list.columnDescription' | translate }}</th>
              <th>{{ 'category.list.columnCreated' | translate }}</th>
              <th class="actions-col">{{ 'common.actions' | translate }}</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr>
              <td>{{ row.name }}</td>
              <td>{{ row.description ?? '—' }}</td>
              <td>{{ row.createdAt | date:'medium' }}</td>
              <td class="actions-col">
                <p-button
                  icon="pi pi-pencil"
                  size="small"
                  severity="secondary"
                  [rounded]="true"
                  [text]="true"
                  [routerLink]="['/categories', row.id, 'edit']"
                />
                <p-button
                  icon="pi pi-trash"
                  size="small"
                  severity="danger"
                  [rounded]="true"
                  [text]="true"
                  (onClick)="confirmDelete(row)"
                />
              </td>
            </tr>
          </ng-template>
        </p-table>
      }
    </div>
  `,
  styles: [`
    .page {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }
    .page-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .page-header h1 {
      margin: 0;
    }
    .empty {
      color: var(--p-text-muted-color, #6b7280);
    }
    .actions-col {
      width: 120px;
      text-align: right;
    }
  `]
})
export class CategoryList {
  private readonly service = inject(CategoryService);
  private readonly confirm = inject(ConfirmationService);
  private readonly messages = inject(MessageService);
  private readonly translate = inject(TranslateService);

  readonly isLoading = signal(true);
  readonly categories = signal<CategoryResponse[]>([]);

  ngOnInit(): void {
    this.load();
  }

  private load(): void {
    this.isLoading.set(true);
    this.service.listCategories().subscribe({
      next: rows => {
        this.categories.set(rows);
        this.isLoading.set(false);
      },
      error: () => {
        this.isLoading.set(false);
      }
    });
  }

  confirmDelete(row: CategoryResponse): void {
    this.confirm.confirm({
      header: this.translate.instant('category.actions.delete.confirmHeader'),
      message: this.translate.instant('category.actions.delete.confirmMessage', { name: row.name }),
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: this.translate.instant('common.delete'),
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: this.translate.instant('common.cancel'),
      accept: () => this.delete(row)
    });
  }

  private delete(row: CategoryResponse): void {
    this.service.deleteCategory(row.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: this.translate.instant('category.actions.delete.successSummary') });
        this.load();
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        const detail =
          err.status === 409
            ? this.translate.instant('category.actions.delete.inUseError')
            : translateApiErrorCode(this.translate, body?.message, 'category.actions.delete.failedDetail');
        this.messages.add({
          severity: 'error',
          summary: this.translate.instant('category.actions.delete.failedSummary'),
          detail
        });
      }
    });
  }
}
