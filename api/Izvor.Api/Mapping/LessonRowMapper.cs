using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class LessonRowMapper
{
    public static LessonResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var courseOrdinal = reader.GetOrdinal("course_id");
        var titleOrdinal = reader.GetOrdinal("title");
        var contentOrdinal = reader.GetOrdinal("content");
        var positionOrdinal = reader.GetOrdinal("position");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");

        return new LessonResponse(
            Id: reader.GetGuid(idOrdinal),
            CourseId: reader.GetGuid(courseOrdinal),
            Title: reader.GetString(titleOrdinal),
            Content: reader.GetString(contentOrdinal),
            Position: reader.GetInt32(positionOrdinal),
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal));
    }
}
