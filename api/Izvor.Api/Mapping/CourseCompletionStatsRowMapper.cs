using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class CourseCompletionStatsRowMapper
{
    public static CourseCompletionStatsResponse Map(NpgsqlDataReader reader)
    {
        var courseOrdinal = reader.GetOrdinal("course_id");
        var totalOrdinal = reader.GetOrdinal("total_enrollments");
        var activeOrdinal = reader.GetOrdinal("active_count");
        var completedOrdinal = reader.GetOrdinal("completed_count");
        var cancelledOrdinal = reader.GetOrdinal("cancelled_count");
        var avgOrdinal = reader.GetOrdinal("average_progress_pct");

        return new CourseCompletionStatsResponse(
            CourseId: reader.GetGuid(courseOrdinal),
            TotalEnrollments: reader.GetInt32(totalOrdinal),
            ActiveCount: reader.GetInt32(activeOrdinal),
            CompletedCount: reader.GetInt32(completedOrdinal),
            CancelledCount: reader.GetInt32(cancelledOrdinal),
            AverageProgressPct: reader.GetDecimal(avgOrdinal));
    }
}
