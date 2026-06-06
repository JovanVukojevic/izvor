namespace Izvor.Api.Dtos;

public sealed record CourseResponse(
    Guid Id,
    Guid[] CategoryIds,
    Guid AuthorId,
    string Title,
    string? Description,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    bool IsActive);
