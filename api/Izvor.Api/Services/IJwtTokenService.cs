namespace Izvor.Api.Services;

public interface IJwtTokenService
{
    string GenerateToken(Guid userId, Guid tenantId, string role, string email);
}
