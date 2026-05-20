using Izvor.Api.Dtos;

namespace Izvor.Api.Extensions;

public static class HttpContextExtensions
{
    public const string TenantContextKey = "Izvor.Tenant";

    public static void SetTenant(this HttpContext context, Tenant tenant)
    {
        context.Items[TenantContextKey] = tenant;
    }

    public static Tenant GetTenant(this HttpContext context)
    {
        return context.Items[TenantContextKey] as Tenant
            ?? throw new InvalidOperationException(
                "Tenant not set in HttpContext. TenantResolutionMiddleware must run before this point.");
    }

    public static Tenant? TryGetTenant(this HttpContext context)
    {
        return context.Items[TenantContextKey] as Tenant;
    }
}
