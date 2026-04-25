import { ErrorHandler, Injectable } from '@angular/core';

const RESIZE_OBSERVER_LOOP_MESSAGE = 'ResizeObserver loop completed with undelivered notifications';

@Injectable()
export class SilentErrorHandler extends ErrorHandler {
  override handleError(error: unknown): void {
    const message = this.extractMessage(error);
    if (message?.includes(RESIZE_OBSERVER_LOOP_MESSAGE)) {
      return;
    }
    super.handleError(error);
  }

  private extractMessage(error: unknown): string | null {
    if (error instanceof Error) return error.message;
    if (error instanceof ErrorEvent) return error.message;
    if (typeof error === 'string') return error;
    return null;
  }
}
