using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class EnrollmentRowMapper
{
    public static EnrollmentResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var courseOrdinal = reader.GetOrdinal("course_id");
        var userOrdinal = reader.GetOrdinal("user_id");
        var statusOrdinal = reader.GetOrdinal("status");
        var enrolledOrdinal = reader.GetOrdinal("enrolled_at");
        var completedOrdinal = reader.GetOrdinal("completed_at");
        var cancelledOrdinal = reader.GetOrdinal("cancelled_at");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");

        return new EnrollmentResponse(
            Id: reader.GetGuid(idOrdinal),
            CourseId: reader.GetGuid(courseOrdinal),
            UserId: reader.GetGuid(userOrdinal),
            Status: reader.GetString(statusOrdinal),
            EnrolledAt: reader.GetDateTime(enrolledOrdinal),
            CompletedAt: reader.IsDBNull(completedOrdinal) ? null : reader.GetDateTime(completedOrdinal),
            CancelledAt: reader.IsDBNull(cancelledOrdinal) ? null : reader.GetDateTime(cancelledOrdinal),
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal));
    }
}
