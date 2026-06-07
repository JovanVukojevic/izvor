namespace Izvor.Api.Dtos;

public sealed record LessonCompletionResponse(
    Guid EnrollmentId,
    Guid LessonId,
    DateTime CompletedAt);
