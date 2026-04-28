using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class LessonProgressRowMapper
{
    public static LessonProgressResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var enrollmentOrdinal = reader.GetOrdinal("enrollment_id");
        var lessonOrdinal = reader.GetOrdinal("lesson_id");
        var completedOrdinal = reader.GetOrdinal("completed_at");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");

        return new LessonProgressResponse(
            Id: reader.GetGuid(idOrdinal),
            EnrollmentId: reader.GetGuid(enrollmentOrdinal),
            LessonId: reader.GetGuid(lessonOrdinal),
            CompletedAt: reader.GetDateTime(completedOrdinal),
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal));
    }
}
