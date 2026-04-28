namespace Izvor.Api.Dtos;

public sealed record CourseResponse(
    Guid Id,
    Guid? CategoryId,
    Guid AuthorId,
    string Title,
    string? Description,
    string Status,
    bool Sequential,
    DateTime CreatedAt,
    DateTime UpdatedAt);
