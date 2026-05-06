export type EnrollmentStatus = 'active' | 'completed' | 'cancelled';

export interface EnrollmentResponse {
  id: string;
  courseId: string;
  userId: string;
  status: EnrollmentStatus;
  enrolledAt: string;
  completedAt: string | null;
  cancelledAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface EnrollUserRequest {
  courseId: string;
  userId: string;
}

export interface LessonProgressResponse {
  id: string;
  enrollmentId: string;
  lessonId: string;
  completedAt: string;
}
