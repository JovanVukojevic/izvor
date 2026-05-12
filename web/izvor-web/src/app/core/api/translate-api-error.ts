import { HttpErrorResponse } from '@angular/common/http';
import { TranslateService } from '@ngx-translate/core';

import { ErrorResponse } from './models/error-response.model';

export function translateApiErrorCode(
  translate: TranslateService,
  code: string | undefined | null,
  fallbackKey = 'error.unknown'
): string {
  if (code) {
    const key = `error.${code}`;
    const translated = translate.instant(key);
    if (translated !== key) {
      return translated;
    }
  }
  return translate.instant(fallbackKey);
}

export function translateApiError(
  translate: TranslateService,
  err: HttpErrorResponse,
  fallbackKey = 'error.unknown'
): string {
  const body = err.error as ErrorResponse | null | undefined;
  return translateApiErrorCode(translate, body?.message, fallbackKey);
}
