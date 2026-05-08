namespace Izvor.Api.Dtos;

public sealed record CourseResponse(
    Guid Id,
    Guid? CategoryId,
    Guid AuthorId,
    string Title,
    string? Description,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    bool IsActive);
