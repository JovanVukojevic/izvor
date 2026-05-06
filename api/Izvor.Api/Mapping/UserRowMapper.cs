using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Mapping;

public static class UserRowMapper
{
    public const string UserSelectColumns =
        "id, email, role, created_at, updated_at, is_active";

    public static UserResponse Map(NpgsqlDataReader reader)
    {
        var idOrdinal = reader.GetOrdinal("id");
        var emailOrdinal = reader.GetOrdinal("email");
        var roleOrdinal = reader.GetOrdinal("role");
        var createdOrdinal = reader.GetOrdinal("created_at");
        var updatedOrdinal = reader.GetOrdinal("updated_at");
        var isActiveOrdinal = reader.GetOrdinal("is_active");

        return new UserResponse(
            Id: reader.GetGuid(idOrdinal),
            Email: reader.GetString(emailOrdinal),
            Role: reader.GetString(roleOrdinal),
            CreatedAt: reader.GetDateTime(createdOrdinal),
            UpdatedAt: reader.GetDateTime(updatedOrdinal),
            IsActive: reader.GetBoolean(isActiveOrdinal));
    }
}
