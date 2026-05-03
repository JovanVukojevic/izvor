import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { RouterLink } from '@angular/router';

import { TableModule } from 'primeng/table';
import { Button } from 'primeng/button';
import { ConfirmationService, MessageService } from 'primeng/api';

import { CategoryService } from '../../../core/api/services/category.service';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { ErrorResponse } from '../../../core/api/models/error-response.model';

@Component({
  selector: 'izvor-category-list',
  imports: [TableModule, Button, RouterLink, DatePipe],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>Categories</h1>
        <p-button label="New Category" icon="pi pi-plus" routerLink="/categories/new" />
      </header>

      @if (isLoading()) {
        <p>Loading categories…</p>
      } @else if (categories().length === 0) {
        <p class="empty">No categories yet. Click "New Category" to create one.</p>
      } @else {
        <p-table [value]="categories()" stripedRows>
          <ng-template pTemplate="header">
            <tr>
              <th>Name</th>
              <th>Description</th>
              <th>Created</th>
              <th class="actions-col">Actions</th>
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
      header: 'Delete category',
      message: `Delete "${row.name}"? This cannot be undone.`,
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Delete',
      acceptButtonStyleClass: 'p-button-danger',
      rejectLabel: 'Cancel',
      accept: () => this.delete(row)
    });
  }

  private delete(row: CategoryResponse): void {
    this.service.deleteCategory(row.id).subscribe({
      next: () => {
        this.messages.add({ severity: 'success', summary: 'Category deleted' });
        this.load();
      },
      error: (err: HttpErrorResponse) => {
        const body = err.error as ErrorResponse | null | undefined;
        const detail =
          err.status === 409
            ? 'Cannot delete this category — it may be in use by courses.'
            : body?.message ?? 'Could not delete the category.';
        this.messages.add({ severity: 'error', summary: 'Delete failed', detail });
      }
    });
  }
}
