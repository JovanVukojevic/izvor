export interface CourseResponse {
  id: string;
  categoryId: string | null;
  authorId: string;
  title: string;
  description: string | null;
  createdAt: string;
  updatedAt: string;
  isActive: boolean;
}

export interface CreateCourseRequest {
  title: string;
  description: string | null;
  categoryId: string | null;
}

export interface UpdateCourseRequest {
  title: string;
  description: string | null;
  categoryId: string | null;
}

export interface CourseCompletionStatsResponse {
  courseId: string;
  totalEnrollments: number;
  activeCount: number;
  completedCount: number;
  cancelledCount: number;
  averageProgressPct: number;
}
