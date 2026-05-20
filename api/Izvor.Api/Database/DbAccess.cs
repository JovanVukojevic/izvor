using System.Reflection;
using System.Security.Claims;
using Dapper;
using Microsoft.IdentityModel.JsonWebTokens;
using Npgsql;

namespace Izvor.Api.Database;

public sealed class DbAccess : IDbAccess
{
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
        var sql = BuildSql(functionName, parameters);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        var result = await connection.QuerySingleOrDefaultAsync<T>(command);
        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public async Task<IReadOnlyList<T>> QueryAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var sql = BuildSql(functionName, parameters);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        var rows = await connection.QueryAsync<T>(command);
        await transaction.CommitAsync(cancellationToken);
        return rows.AsList();
    }

    public async Task ExecuteAsync(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var sql = BuildSql(functionName, parameters);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ApplySessionContextAsync(connection, transaction, cancellationToken);
        var command = new CommandDefinition(sql, parameters, transaction, cancellationToken: cancellationToken);
        await connection.ExecuteAsync(command);
        await transaction.CommitAsync(cancellationToken);
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

        var command = new CommandDefinition(
            "SELECT set_config('app.current_tenant', @t, true), " +
            "       set_config('app.current_user', @u, true)",
            new { t = tenantId.ToString(), u = userId.ToString() },
            transaction,
            cancellationToken: cancellationToken);
        await connection.ExecuteAsync(command);
    }
}
