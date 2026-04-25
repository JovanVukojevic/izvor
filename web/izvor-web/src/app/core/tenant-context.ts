import { Injectable } from '@angular/core';
import { environment } from '../../environments/environment';

@Injectable({ providedIn: 'root' })
export class TenantContextService {
  readonly subdomain: string | null;
  readonly isTenantContext: boolean;

  constructor() {
    const hostname = window.location.hostname;
    this.subdomain = TenantContextService.resolveSubdomain(hostname, environment.tenantBaseDomain);
    this.isTenantContext = this.subdomain !== null && this.subdomain !== '';

    if (this.isTenantContext) {
      console.log(`[TenantContext] resolved subdomain: "${this.subdomain}"`);
    } else {
      console.log(`[TenantContext] no tenant subdomain detected (hostname: "${hostname}")`);
    }
  }

  private static resolveSubdomain(hostname: string, baseDomain: string): string | null {
    const host = hostname.toLowerCase();
    const suffix = '.' + baseDomain.toLowerCase();
    if (!host.endsWith(suffix)) {
      return null;
    }
    const prefix = host.slice(0, host.length - suffix.length);
    return prefix === '' ? null : prefix;
  }
}
