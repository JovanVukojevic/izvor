import { UserRole } from '../../auth/role.utils';

export interface UserResponse {
  id: string;
  email: string;
  role: UserRole;
  createdAt: string;
  updatedAt: string;
  isActive: boolean;
}

export interface CreateUserRequest {
  email: string;
  password: string;
  role: UserRole;
}

export interface ListUsersQuery {
  role?: UserRole;
  isActive?: boolean;
}

export interface AdminResetPasswordRequest {
  newPassword: string;
}
