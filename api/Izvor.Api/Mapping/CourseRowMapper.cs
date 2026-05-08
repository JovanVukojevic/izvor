using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class CourseRowMapper
{
    public static CourseResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var categoryOrdinal = reader.GetOrdinal("category_id");
        var authorOrdinal = reader.GetOrdinal("author_id");
        var titleOrdinal = reader.GetOrdinal("title");
        var descOrdinal = reader.GetOrdinal("description");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");
        var activeOrdinal = reader.GetOrdinal("is_active");

        return new CourseResponse(
            Id: reader.GetGuid(idOrdinal),
            CategoryId: reader.IsDBNull(categoryOrdinal) ? null : reader.GetGuid(categoryOrdinal),
            AuthorId: reader.GetGuid(authorOrdinal),
            Title: reader.GetString(titleOrdinal),
            Description: reader.IsDBNull(descOrdinal) ? null : reader.GetString(descOrdinal),
            Status: "draft", // Placeholder until Prompt 2 removes the DTO field.
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal),
            IsActive: reader.GetBoolean(activeOrdinal));
    }
}
