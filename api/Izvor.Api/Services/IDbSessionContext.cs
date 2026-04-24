using Npgsql;

namespace Izvor.Api.Services;

public interface IDbSessionContext
{
    Task BeginAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    NpgsqlCommand CreateCommand(string sql);
    Task CommitAsync(CancellationToken cancellationToken);
}
