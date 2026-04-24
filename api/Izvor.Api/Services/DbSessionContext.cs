using Npgsql;

namespace Izvor.Api.Services;

public sealed class DbSessionContext : IDbSessionContext, IAsyncDisposable
{
    private readonly NpgsqlDataSource _dataSource;
    private NpgsqlConnection? _connection;
    private NpgsqlTransaction? _transaction;
    private bool _committed;

    public DbSessionContext(NpgsqlDataSource dataSource)
    {
        _dataSource = dataSource;
    }

    public async Task BeginAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        if (_connection is not null)
        {
            throw new InvalidOperationException("DbSessionContext is already initialized");
        }

        _connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        _transaction = await _connection.BeginTransactionAsync(cancellationToken);

        await using var setCommand = new NpgsqlCommand(
            "SELECT set_config('app.current_tenant', @t, true), " +
            "       set_config('app.current_user', @u, true)",
            _connection, _transaction);
        setCommand.Parameters.AddWithValue("t", tenantId.ToString());
        setCommand.Parameters.AddWithValue("u", userId.ToString());
        await setCommand.ExecuteNonQueryAsync(cancellationToken);
    }

    public NpgsqlCommand CreateCommand(string sql)
    {
        if (_connection is null || _transaction is null)
        {
            throw new InvalidOperationException(
                "DbSessionContext is not initialized. BeginAsync must be called first.");
        }
        return new NpgsqlCommand(sql, _connection, _transaction);
    }

    public async Task CommitAsync(CancellationToken cancellationToken)
    {
        if (_transaction is null)
        {
            throw new InvalidOperationException(
                "DbSessionContext has no active transaction to commit");
        }
        await _transaction.CommitAsync(cancellationToken);
        _committed = true;
    }

    public async ValueTask DisposeAsync()
    {
        if (_transaction is not null)
        {
            if (!_committed)
            {
                try
                {
                    await _transaction.RollbackAsync();
                }
                catch
                {
                }
            }
            await _transaction.DisposeAsync();
        }
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }
    }
}
