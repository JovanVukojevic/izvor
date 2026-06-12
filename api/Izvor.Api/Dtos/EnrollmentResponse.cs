namespace Izvor.Api.Dtos;

public sealed record EnrollmentResponse(
    Guid Id,
    Guid CourseId,
    Guid UserId,
    string Status,
    DateTime EnrolledAt,
    DateTime? FinishedAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);
