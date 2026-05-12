import { ApplicationConfig, ErrorHandler, inject, provideAppInitializer, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { providePrimeNG } from 'primeng/config';
import { ConfirmationService, MessageService } from 'primeng/api';
import { provideTranslateService } from '@ngx-translate/core';
import { provideTranslateHttpLoader } from '@ngx-translate/http-loader';
import Aura from '@primeuix/themes/aura';
import { firstValueFrom } from 'rxjs';

import { routes } from './app.routes';
import { environment } from '../environments/environment';
import { API_BASE_URL } from './core/api-base-url.token';
import { TenantContextService } from './core/tenant-context';
import { AuthService } from './core/auth/auth.service';
import { LanguageService } from './core/i18n/language.service';
import { DEFAULT_LOCALE } from './core/i18n/locale.model';
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
    provideTranslateService({ lang: DEFAULT_LOCALE, fallbackLang: 'en' }),
    provideTranslateHttpLoader({ prefix: '/i18n/', suffix: '.json' }),
    provideAppInitializer(() => {
      inject(TenantContextService);
    }),
    provideAppInitializer(async () => {
      try {
        await firstValueFrom(inject(LanguageService).loadInitialLocale());
      } catch {
        // Translations failed to load — UI falls back to raw keys; first-frame stability is best-effort.
      }
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
