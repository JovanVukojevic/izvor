import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from './auth.service';
import { UserRole, hasRole } from './role.utils';

export const roleGuard: CanActivateFn = route => {
  const auth = inject(AuthService);
  const router = inject(Router);
  const required = route.data['minRole'] as UserRole | undefined;
  const actual = auth.currentUser()?.role;
  if (!required || hasRole(actual, required)) {
    return true;
  }
  return router.createUrlTree(['/courses']);
};
