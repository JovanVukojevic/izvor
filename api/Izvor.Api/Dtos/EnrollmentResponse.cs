namespace Izvor.Api.Dtos;

public sealed record EnrollmentResponse(
    Guid Id,
    Guid CourseId,
    Guid UserId,
    string Status,
    DateTime EnrolledAt,
    DateTime? CompletedAt,
    DateTime? CancelledAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);
