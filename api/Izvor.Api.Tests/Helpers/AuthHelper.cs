using Izvor.Api.Services;
using Microsoft.Extensions.DependencyInjection;

namespace Izvor.Api.Tests.Helpers;

public static class AuthHelper
{
    public static string MintToken(IServiceProvider services, Guid userId, Guid tenantId, string role, string email)
    {
        // IJwtTokenService is scoped — must resolve through a scope to satisfy the
        // ServiceProvider scope validator (enabled in Development).
        using var scope = services.CreateScope();
        var tokenService = scope.ServiceProvider.GetRequiredService<IJwtTokenService>();
        return tokenService.GenerateToken(userId, tenantId, role, email);
    }
}
