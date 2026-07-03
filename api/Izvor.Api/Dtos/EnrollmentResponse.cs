namespace Izvor.Api.Dtos;

public sealed record EnrollmentResponse
{
    public Guid Id { get; init; }
    public Guid CourseId { get; init; }
    public Guid UserId { get; init; }
    public string Status { get; init; } = string.Empty;
    public DateTime EnrolledAt { get; init; }
    public DateTime? FinishedAt { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
    public string? UserEmail { get; init; }
}
