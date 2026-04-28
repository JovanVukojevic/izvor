namespace Izvor.Api.Dtos;

public sealed record CourseCompletionStatsResponse(
    Guid CourseId,
    int TotalEnrollments,
    int ActiveCount,
    int CompletedCount,
    int CancelledCount,
    decimal AverageProgressPct);
