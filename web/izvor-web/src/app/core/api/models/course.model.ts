export interface CourseResponse {
  id: string;
  categoryIds: string[];
  authorId: string;
  authorEmail: string | null;
  title: string;
  description: string | null;
  createdAt: string;
  updatedAt: string;
  isActive: boolean;
}

export interface CreateLessonInput {
  title: string;
  content: string;
}

export interface CreateCourseRequest {
  title: string;
  description: string | null;
  categoryIds: string[];
  lessons: CreateLessonInput[];
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
