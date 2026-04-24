using System.Text.Json;
using Izvor.Api.Extensions;
using Izvor.Api.Models;

namespace Izvor.Api.Middleware;

public sealed class JwtTenantMatchMiddleware
{
    private readonly RequestDelegate _next;
    private readonly JsonSerializerOptions _jsonOptions;

    public JwtTenantMatchMiddleware(RequestDelegate next, JsonSerializerOptions jsonOptions)
    {
        _next = next;
        _jsonOptions = jsonOptions;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.User.Identity?.IsAuthenticated != true)
        {
            await _next(context);
            return;
        }

        var tenantClaim = context.User.FindFirst("tenant_id")?.Value;
        if (string.IsNullOrEmpty(tenantClaim) || !Guid.TryParse(tenantClaim, out var jwtTenantId))
        {
            await WriteErrorAsync(context, StatusCodes.Status401Unauthorized,
                "invalid_token",
                "Token is missing or has an invalid tenant claim");
            return;
        }

        var resolvedTenant = context.GetTenant();
        if (jwtTenantId != resolvedTenant.Id)
        {
            await WriteErrorAsync(context, StatusCodes.Status403Forbidden,
                "tenant_mismatch",
                "Token was issued for a different tenant than the requested subdomain");
            return;
        }

        await _next(context);
    }

    private async Task WriteErrorAsync(HttpContext context, int statusCode, string error, string message)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        var payload = new ErrorResponse(error, message);
        await JsonSerializer.SerializeAsync(context.Response.Body, payload, _jsonOptions);
    }
}
