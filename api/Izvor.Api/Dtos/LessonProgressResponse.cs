namespace Izvor.Api.Dtos;

public sealed record LessonProgressResponse(
    Guid EnrollmentId,
    Guid LessonId,
    DateTime CompletedAt);
