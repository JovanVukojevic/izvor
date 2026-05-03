export interface LoginRequest {
  email: string;
  password: string;
}

export interface TenantInfo {
  id: string;
  name: string;
  subdomain: string;
}

export interface UserInfo {
  id: string;
  email: string;
  role: 'admin' | 'author' | 'learner';
  tenant: TenantInfo;
}

export interface LoginResponse {
  accessToken: string;
  user: UserInfo;
}

export interface ApiErrorResponse {
  error: string;
  message: string;
}
