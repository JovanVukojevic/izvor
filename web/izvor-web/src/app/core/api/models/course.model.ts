export interface CourseResponse {
  id: string;
  categoryIds: string[];
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
  categoryIds: string[];
  firstLessonTitle: string;
  firstLessonContent: string;
}

export interface UpdateCourseRequest {
  title: string;
  description: string | null;
  categoryIds: string[];
}

export interface CourseCompletionStatsResponse {
  courseId: string;
  totalEnrollments: number;
  activeCount: number;
  completedCount: number;
  cancelledCount: number;
  averageProgressPct: number;
}
