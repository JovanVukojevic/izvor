using System.Data;
using Dapper;
using Npgsql;
using NpgsqlTypes;

namespace Izvor.Api.Database;

// Sends a pre-serialized JSON string as a jsonb parameter. The data source is built
// without EnableDynamicJson, so a plain string maps to text and text -> jsonb is not an
// implicit cast (function-overload resolution would fail). DbAccess.BuildSql emits a bare
// @param with no cast, so the type must be set on the parameter itself. Dapper invokes
// AddParameter for property values whose static type implements ICustomQueryParameter
// (the same mechanism Dapper's built-in DbString uses).
public sealed class JsonbParameter : SqlMapper.ICustomQueryParameter
{
    private readonly string _json;

    public JsonbParameter(string json) => _json = json;

    public void AddParameter(IDbCommand command, string name)
        => command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Jsonb) { Value = _json });
}
