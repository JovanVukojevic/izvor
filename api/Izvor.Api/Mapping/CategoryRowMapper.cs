using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class CategoryRowMapper
{
    public static CategoryResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var nameOrdinal = reader.GetOrdinal("name");
        var descOrdinal = reader.GetOrdinal("description");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");

        return new CategoryResponse(
            Id: reader.GetGuid(idOrdinal),
            Name: reader.GetString(nameOrdinal),
            Description: reader.IsDBNull(descOrdinal) ? null : reader.GetString(descOrdinal),
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal));
    }
}
