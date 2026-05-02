export interface LessonResponse {
  id: string;
  courseId: string;
  title: string;
  content: string;
  position: number;
  createdAt: string;
  updatedAt: string;
}

export interface CreateLessonRequest {
  title: string;
  content: string;
}

export interface UpdateLessonRequest {
  title: string;
  content: string;
}

export interface ReorderLessonRequest {
  position: number;
}
