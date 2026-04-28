namespace Izvor.Api.Dtos;

public sealed record LessonProgressResponse(
    Guid Id,
    Guid EnrollmentId,
    Guid LessonId,
    DateTime CompletedAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);
