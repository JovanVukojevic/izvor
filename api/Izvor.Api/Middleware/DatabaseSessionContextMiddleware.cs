using System.Security.Claims;
using Izvor.Api.Services;
using Microsoft.IdentityModel.JsonWebTokens;

namespace Izvor.Api.Middleware;

public sealed class DatabaseSessionContextMiddleware
{
    private readonly RequestDelegate _next;

    public DatabaseSessionContextMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, IDbSessionContext session)
    {
        if (context.User.Identity?.IsAuthenticated != true)
        {
            await _next(context);
            return;
        }

        var userIdClaim = context.User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
                          ?? context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var tenantIdClaim = context.User.FindFirst("tenant_id")?.Value;

        if (string.IsNullOrEmpty(userIdClaim) ||
            !Guid.TryParse(userIdClaim, out var userId) ||
            string.IsNullOrEmpty(tenantIdClaim) ||
            !Guid.TryParse(tenantIdClaim, out var tenantId))
        {
            await _next(context);
            return;
        }

        await session.BeginAsync(tenantId, userId, context.RequestAborted);
        await _next(context);
        await session.CommitAsync(context.RequestAborted);
    }
}
