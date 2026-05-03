export type UserRole = 'admin' | 'author' | 'learner';

const RANK: Record<UserRole, number> = {
  learner: 0,
  author: 1,
  admin: 2
};

export function hasRole(actual: UserRole | undefined, required: UserRole): boolean {
  return actual !== undefined && RANK[actual] >= RANK[required];
}
