namespace Izvor.Api.Dtos;

public sealed record ListUsersQuery(string? Role, bool? IsActive);
