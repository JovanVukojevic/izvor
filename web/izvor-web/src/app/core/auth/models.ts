export interface LoginRequest {
  email: string;
  password: string;
}

export interface UserInfo {
  id: string;
  email: string;
  role: 'admin' | 'author' | 'learner';
}

export interface LoginResponse {
  accessToken: string;
  user: UserInfo;
}

export interface ApiErrorResponse {
  error: string;
  message: string;
}
