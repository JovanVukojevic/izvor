using System.Reflection;
using System.Security.Claims;
using Dapper;
using Microsoft.IdentityModel.JsonWebTokens;
using Npgsql;

namespace Izvor.Api.Database;

public sealed class DbAccess : IDbAccess
{
    private const string TenantSetting = "app.current_tenant";
    private const string UserSetting = "app.current_user";

    private readonly NpgsqlDataSource _dataSource;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public DbAccess(NpgsqlDataSource dataSource, IHttpContextAccessor httpContextAccessor)
    {
        _dataSource = dataSource;
        _httpContextAccessor = httpContextAccessor;
    }

    public async Task<T?> CallAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        var result = await CallCoreAsync<T>(connection, transaction, functionName, parameters, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public async Task<IReadOnlyList<T>> QueryAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        var rows = await QueryCoreAsync<T>(connection, transaction, functionName, parameters, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return rows;
    }

    public async Task ExecuteAsync(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        await ExecuteCoreAsync(connection, transaction, functionName, parameters, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<T> InTransactionAsync<T>(
        Func<IDbTransactionScope, Task<T>> work,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var scope = new DbTransactionScope(connection, transaction);

        var result = await work(scope);
        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public Task InTransactionAsync(
        Func<IDbTransactionScope, Task> work,
        CancellationToken cancellationToken = default)
        => InTransactionAsync(async scope =>
        {
            await work(scope);
            return true;
        }, cancellationToken);

    private async Task ApplySessionContextAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        var httpContext = _httpContextAccessor.HttpContext
            ?? throw new InvalidOperationException(
                "IDbAccess called without an active HttpContext");

        var userIdClaim = httpContext.User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
                          ?? httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var tenantIdClaim = httpContext.User.FindFirst("tenant_id")?.Value;

        if (string.IsNullOrEmpty(userIdClaim) ||
            !Guid.TryParse(userIdClaim, out var userId) ||
            string.IsNullOrEmpty(tenantIdClaim) ||
            !Guid.TryParse(tenantIdClaim, out var tenantId))
        {
            throw new InvalidOperationException(
                "IDbAccess requires authenticated tenant and user claims");
        }

        await SetContextAsync(
            connection,
            transaction,
            [
                (TenantSetting, tenantId.ToString()),
                (UserSetting, userId.ToString())
            ],
            cancellationToken);
    }

    private static async Task SetContextAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        IReadOnlyList<(string Key, string Value)> settings,
        CancellationToken cancellationToken)
    {
        if (settings.Count == 0)
        {
            return;
        }

        var clauses = string.Join(", ", settings.Select((_, i) => $"set_config(@k{i}, @v{i}, true)"));
        var parameters = new DynamicParameters();
        for (var i = 0; i < settings.Count; i++)
        {
            parameters.Add($"k{i}", settings[i].Key);
            parameters.Add($"v{i}", settings[i].Value);
        }

        var command = new CommandDefinition(
            "SELECT " + clauses, parameters, transaction, cancellationToken: cancellationToken);
        await connection.ExecuteAsync(command);
    }

    private static async Task<T?> CallCoreAsync<T>(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string functionName,
        object? parameters,
        CancellationToken cancellationToken)
    {
        var sql = BuildSql(functionName, parameters);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<T>(command);
    }

    private static async Task<IReadOnlyList<T>> QueryCoreAsync<T>(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string functionName,
        object? parameters,
        CancellationToken cancellationToken)
    {
        var sql = BuildSql(functionName, parameters);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        var rows = await connection.QueryAsync<T>(command);
        return rows.AsList();
    }

    private static async Task ExecuteCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string functionName,
        object? parameters,
        CancellationToken cancellationToken)
    {
        var sql = BuildSql(functionName, parameters);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        await connection.ExecuteAsync(command);
    }

    private static string BuildSql(string functionName, object? parameters)
    {
        if (parameters is null)
        {
            return $"SELECT * FROM {functionName}()";
        }
        var props = parameters.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance);
        var args = string.Join(", ", props.Select(p => "@" + p.Name));
        return $"SELECT * FROM {functionName}({args})";
    }

    private sealed class DbTransactionScope : IDbTransactionScope
    {
        private readonly NpgsqlConnection _connection;
        private readonly NpgsqlTransaction _transaction;

        public DbTransactionScope(NpgsqlConnection connection, NpgsqlTransaction transaction)
        {
            _connection = connection;
            _transaction = transaction;
        }

        public Task SetTenantAsync(Guid tenantId, CancellationToken cancellationToken = default)
            => SetContextAsync(
                _connection, _transaction,
                [(TenantSetting, tenantId.ToString())],
                cancellationToken);

        public Task SetUserAsync(Guid userId, CancellationToken cancellationToken = default)
            => SetContextAsync(
                _connection, _transaction,
                [(UserSetting, userId.ToString())],
                cancellationToken);

        public Task<T?> CallAsync<T>(
            string functionName,
            object? parameters = null,
            CancellationToken cancellationToken = default)
            => CallCoreAsync<T>(_connection, _transaction, functionName, parameters, cancellationToken);

        public Task<IReadOnlyList<T>> QueryAsync<T>(
            string functionName,
            object? parameters = null,
            CancellationToken cancellationToken = default)
            => QueryCoreAsync<T>(_connection, _transaction, functionName, parameters, cancellationToken);

        public Task ExecuteAsync(
            string functionName,
            object? parameters = null,
            CancellationToken cancellationToken = default)
            => ExecuteCoreAsync(_connection, _transaction, functionName, parameters, cancellationToken);
    }
}
