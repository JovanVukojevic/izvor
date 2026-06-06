export interface CourseResponse {
  id: string;
  categoryId: string;
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
  categoryId: string;
  firstLessonTitle: string;
  firstLessonContent: string;
}

export interface UpdateCourseRequest {
  title: string;
  description: string | null;
  categoryId: string;
}

export interface CourseCompletionStatsResponse {
  courseId: string;
  totalEnrollments: number;
  activeCount: number;
  completedCount: number;
  cancelledCount: number;
  averageProgressPct: number;
}
