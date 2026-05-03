import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';

import { TableModule } from 'primeng/table';
import { Select } from 'primeng/select';
import { Button } from 'primeng/button';
import { Tag } from 'primeng/tag';
import { FormsModule } from '@angular/forms';

import { CourseService } from '../../../core/api/services/course.service';
import { CategoryService } from '../../../core/api/services/category.service';
import { CourseResponse, CourseStatus } from '../../../core/api/models/course.model';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { RequiresRoleDirective } from '../../../core/auth/role.directive';
import { AuthService } from '../../../core/auth/auth.service';

interface StatusOption {
  label: string;
  value: CourseStatus | 'all';
}

interface CategoryOption {
  label: string;
  value: string | 'all';
}

@Component({
  selector: 'izvor-course-list',
  imports: [TableModule, Select, Button, Tag, FormsModule, RouterLink, RequiresRoleDirective],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>Courses</h1>
        <p-button
          *izvorRequiresRole="'author'"
          label="New Course"
          icon="pi pi-plus"
          routerLink="/courses/new"
        />
      </header>

      <div class="filters">
        <div class="filter">
          <label>Status</label>
          <p-select
            [options]="statusOptions"
            [(ngModel)]="statusFilter"
            (onChange)="reload()"
            optionLabel="label"
            optionValue="value"
            styleClass="filter-select"
          />
        </div>
        <div class="filter">
          <label>Category</label>
          <p-select
            [options]="categoryOptions()"
            [(ngModel)]="categoryFilter"
            (onChange)="reload()"
            optionLabel="label"
            optionValue="value"
            styleClass="filter-select"
          />
        </div>
      </div>

      @if (isLoading()) {
        <p>Loading courses…</p>
      } @else if (courses().length === 0) {
        <p class="empty">No courses match the selected filters.</p>
      } @else {
        <p-table [value]="courses()" stripedRows [rowHover]="true">
          <ng-template pTemplate="header">
            <tr>
              <th>Title</th>
              <th>Category</th>
              <th>Status</th>
              <th>Sequential</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr class="row-clickable" (click)="open(row)">
              <td>{{ row.title }}</td>
              <td>{{ categoryName(row.categoryId) }}</td>
              <td><p-tag [value]="row.status" [severity]="statusSeverity(row.status)" /></td>
              <td>{{ row.sequential ? 'Yes' : 'No' }}</td>
            </tr>
          </ng-template>
        </p-table>
      }
    </div>
  `,
  styles: [`
    .page { display: flex; flex-direction: column; gap: 1rem; }
    .page-header { display: flex; justify-content: space-between; align-items: center; }
    .page-header h1 { margin: 0; }
    .filters { display: flex; gap: 1rem; flex-wrap: wrap; }
    .filter { display: flex; flex-direction: column; gap: 0.25rem; }
    .filter label { font-size: 0.85rem; color: var(--p-text-muted-color, #6b7280); }
    :host ::ng-deep .filter-select { min-width: 200px; }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    .row-clickable { cursor: pointer; }
  `]
})
export class CourseList {
  private readonly courseService = inject(CourseService);
  private readonly categoryService = inject(CategoryService);
  private readonly router = inject(Router);
  private readonly auth = inject(AuthService);

  readonly statusOptions: StatusOption[] = [
    { label: 'All', value: 'all' },
    { label: 'Draft', value: 'draft' },
    { label: 'Published', value: 'published' },
    { label: 'Archived', value: 'archived' }
  ];

  statusFilter: CourseStatus | 'all' = this.defaultStatusForRole();
  categoryFilter: string | 'all' = 'all';

  readonly isLoading = signal(true);
  readonly courses = signal<CourseResponse[]>([]);
  readonly categories = signal<CategoryResponse[]>([]);

  readonly categoryOptions = computed<CategoryOption[]>(() => [
    { label: 'Any category', value: 'all' },
    ...this.categories().map(c => ({ label: c.name, value: c.id }))
  ]);

  ngOnInit(): void {
    this.isLoading.set(true);
    forkJoin({
      cats: this.categoryService.listCategories(),
      courses: this.fetchCourses()
    }).subscribe({
      next: ({ cats, courses }) => {
        this.categories.set(cats);
        this.courses.set(courses);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  reload(): void {
    this.isLoading.set(true);
    this.fetchCourses().subscribe({
      next: rows => {
        this.courses.set(rows);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  private fetchCourses() {
    return this.courseService.listCourses({
      status: this.statusFilter === 'all' ? undefined : this.statusFilter,
      categoryId: this.categoryFilter === 'all' ? undefined : this.categoryFilter
    });
  }

  open(row: CourseResponse): void {
    this.router.navigate(['/courses', row.id]);
  }

  categoryName(id: string | null): string {
    if (id === null) return '—';
    return this.categories().find(c => c.id === id)?.name ?? '—';
  }

  statusSeverity(status: CourseStatus): 'success' | 'info' | 'secondary' {
    if (status === 'published') return 'success';
    if (status === 'draft') return 'info';
    return 'secondary';
  }

  private defaultStatusForRole(): CourseStatus | 'all' {
    const role = this.auth.currentUser()?.role;
    return role === 'admin' || role === 'author' ? 'all' : 'published';
  }
}
