export type EnrollmentStatus = 'active' | 'completed' | 'cancelled';

export interface EnrollmentResponse {
  id: string;
  courseId: string;
  userId: string;
  userEmail: string | null;
  status: EnrollmentStatus;
  enrolledAt: string;
  finishedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface EnrollUserRequest {
  courseId: string;
  userId: string;
}

export interface LessonCompletionResponse {
  enrollmentId: string;
  lessonId: string;
  completedAt: string;
}
