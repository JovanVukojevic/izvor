namespace Izvor.Api.Dtos;

public sealed record LessonResponse(
    Guid Id,
    Guid CourseId,
    string Title,
    string Content,
    int Position,
    DateTime CreatedAt,
    DateTime UpdatedAt);
