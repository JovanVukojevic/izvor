import { ApplicationConfig, ErrorHandler, inject, provideAppInitializer, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { providePrimeNG } from 'primeng/config';
import { ConfirmationService, MessageService } from 'primeng/api';
import Aura from '@primeuix/themes/aura';
import { firstValueFrom } from 'rxjs';

import { routes } from './app.routes';
import { environment } from '../environments/environment';
import { API_BASE_URL } from './core/api-base-url.token';
import { TenantContextService } from './core/tenant-context';
import { AuthService } from './core/auth/auth.service';
import { authInterceptor } from './core/auth/auth.interceptor';
import { errorInterceptor } from './core/api/error.interceptor';
import { SilentErrorHandler } from './core/silent-error-handler';

export const appConfig: ApplicationConfig = {
  providers: [
    { provide: ErrorHandler, useClass: SilentErrorHandler },
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([errorInterceptor, authInterceptor])),
    MessageService,
    ConfirmationService,
    provideAppInitializer(() => {
      inject(TenantContextService);
    }),
    provideAppInitializer(async () => {
      const authService = inject(AuthService);
      try {
        await firstValueFrom(authService.refreshAccessToken());
        await firstValueFrom(authService.fetchCurrentUser());
      } catch {
        // No session or expired/revoked cookie — normal first-visit case.
        // refreshAccessToken() already cleared local state on failure.
      }
    }),
    providePrimeNG({ theme: { preset: Aura } }),
    {
      provide: API_BASE_URL,
      useFactory: () => `${window.location.protocol}//${window.location.hostname}:${environment.apiPort}`
    }
  ]
};
