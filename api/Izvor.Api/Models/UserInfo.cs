namespace Izvor.Api.Models;

public sealed record UserInfo(Guid Id, string Email, string Role, TenantInfo Tenant);

public sealed record TenantInfo(Guid Id, string Name, string Subdomain);
