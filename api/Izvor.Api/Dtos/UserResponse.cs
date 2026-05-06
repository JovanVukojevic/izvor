namespace Izvor.Api.Dtos;

public sealed record UserResponse(
    Guid Id,
    string Email,
    string Role,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    bool IsActive);
