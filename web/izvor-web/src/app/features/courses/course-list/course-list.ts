import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';

import { TableModule } from 'primeng/table';
import { Select } from 'primeng/select';
import { Button } from 'primeng/button';
import { Tag } from 'primeng/tag';
import { FormsModule } from '@angular/forms';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { CourseService } from '../../../core/api/services/course.service';
import { CategoryService } from '../../../core/api/services/category.service';
import { CourseResponse } from '../../../core/api/models/course.model';
import { CategoryResponse } from '../../../core/api/models/category.model';
import { RequiresRoleDirective } from '../../../core/auth/role.directive';
import { LanguageService } from '../../../core/i18n/language.service';
import { CourseActivityLabelPipe } from '../../../core/i18n/course-activity-label.pipe';

interface CategoryOption {
  label: string;
  value: string | 'all';
}

type ActiveFilter = 'active' | 'inactive' | 'all';

interface ActiveOption {
  label: string;
  value: ActiveFilter;
}

@Component({
  selector: 'izvor-course-list',
  imports: [TableModule, Select, Button, Tag, FormsModule, RouterLink, RequiresRoleDirective, TranslateModule, CourseActivityLabelPipe],
  template: `
    <div class="page">
      <header class="page-header">
        <h1>{{ 'course.list.title' | translate }}</h1>
        <p-button
          *izvorRequiresRole="'author'"
          [label]="'course.list.new' | translate"
          icon="pi pi-plus"
          routerLink="/courses/new"
        />
      </header>

      <div class="filters">
        <div class="filter">
          <label>{{ 'course.list.filterActivity' | translate }}</label>
          <p-select
            [options]="activeOptions()"
            [(ngModel)]="activeFilter"
            (onChange)="reload()"
            optionLabel="label"
            optionValue="value"
            styleClass="filter-select"
          />
        </div>
        <div class="filter">
          <label>{{ 'course.list.filterCategory' | translate }}</label>
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
        <p>{{ 'course.list.loading' | translate }}</p>
      } @else if (courses().length === 0) {
        <p class="empty">{{ 'course.list.empty' | translate }}</p>
      } @else {
        <p-table [value]="courses()" stripedRows [rowHover]="true">
          <ng-template pTemplate="header">
            <tr>
              <th>{{ 'course.list.columnTitle' | translate }}</th>
              <th>{{ 'course.list.columnCategory' | translate }}</th>
            </tr>
          </ng-template>
          <ng-template pTemplate="body" let-row>
            <tr class="row-clickable" (click)="open(row)">
              <td>
                <span>{{ row.title }}</span>
                @if (!row.isActive) {
                  <p-tag [value]="false | courseActivityLabel" severity="warn" styleClass="inactive-badge" />
                }
              </td>
              <td>
                <div class="category-chips">
                  @for (id of row.categoryIds; track id) {
                    <p-tag [value]="categoryName(id)" severity="info" />
                  }
                </div>
              </td>
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
    :host ::ng-deep .inactive-badge { margin-left: 0.5rem; }
    .category-chips { display: flex; flex-wrap: wrap; gap: 0.25rem; }
    .empty { color: var(--p-text-muted-color, #6b7280); }
    .row-clickable { cursor: pointer; }
  `]
})
export class CourseList {
  private readonly courseService = inject(CourseService);
  private readonly categoryService = inject(CategoryService);
  private readonly router = inject(Router);
  private readonly translate = inject(TranslateService);
  private readonly languageService = inject(LanguageService);

  readonly activeOptions = computed<ActiveOption[]>(() => {
    this.languageService.currentLocale();
    return [
      { label: this.translate.instant('course.activity.active'), value: 'active' },
      { label: this.translate.instant('course.activity.inactive'), value: 'inactive' },
      { label: this.translate.instant('course.activity.all'), value: 'all' }
    ];
  });

  activeFilter: ActiveFilter = 'active';
  // Deliberately single-select: backend api.list_courses takes a single UUID and
  // handles membership server-side (a course matches if the filter category is
  // among its tags). Extending to multi-category filtering is just an array
  // param + ANY filter on the backend plus p-multiselect here; omitted now to
  // keep this pass bounded to the M:N display change.
  categoryFilter: string | 'all' = 'all';

  readonly isLoading = signal(true);
  readonly courses = signal<CourseResponse[]>([]);
  readonly categories = signal<CategoryResponse[]>([]);

  readonly categoryOptions = computed<CategoryOption[]>(() => {
    this.languageService.currentLocale();
    return [
      { label: this.translate.instant('course.list.anyCategory'), value: 'all' },
      ...this.categories().map(c => ({ label: c.name, value: c.id }))
    ];
  });

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
      active: this.activeFilter === 'all' ? undefined : this.activeFilter === 'active',
      categoryId: this.categoryFilter === 'all' ? undefined : this.categoryFilter
    });
  }

  open(row: CourseResponse): void {
    this.router.navigate(['/courses', row.id]);
  }

  categoryName(id: string): string {
    return this.categories().find(c => c.id === id)?.name ?? '—';
  }
}
