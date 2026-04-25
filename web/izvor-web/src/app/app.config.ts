import { ApplicationConfig, inject, provideAppInitializer, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { providePrimeNG } from 'primeng/config';
import Aura from '@primeuix/themes/aura';

import { routes } from './app.routes';
import { environment } from '../environments/environment';
import { API_BASE_URL } from './core/api-base-url.token';
import { TenantContextService } from './core/tenant-context';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideHttpClient(),
    provideAppInitializer(() => {
      inject(TenantContextService);
    }),
    providePrimeNG({ theme: { preset: Aura } }),
    {
      provide: API_BASE_URL,
      useFactory: () => `${window.location.protocol}//${window.location.hostname}:${environment.apiPort}`
    }
  ]
};
