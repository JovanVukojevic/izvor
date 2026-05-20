namespace Izvor.Api.Dtos;

public sealed record Tenant(
    Guid Id,
    string Name,
    string Code,
    string Subdomain,
    string Status,
    DateTime CreatedAt,
    DateTime UpdatedAt);
