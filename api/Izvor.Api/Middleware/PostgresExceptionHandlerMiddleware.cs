using System.Security.Claims;
using System.Text.Json;
using Izvor.Api.Errors;
using Izvor.Api.Extensions;
using Microsoft.IdentityModel.JsonWebTokens;
using Npgsql;
using NpgsqlTypes;

namespace Izvor.Api.Middleware;

public sealed class PostgresExceptionHandlerMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<PostgresExceptionHandlerMiddleware> _logger;
    private readonly JsonSerializerOptions _jsonOptions;

    public PostgresExceptionHandlerMiddleware(
        RequestDelegate next,
        ILogger<PostgresExceptionHandlerMiddleware> logger,
        JsonSerializerOptions jsonOptions)
    {
        _next = next;
        _logger = logger;
        _jsonOptions = jsonOptions;
    }

    public async Task InvokeAsync(HttpContext context, NpgsqlDataSource dataSource)
    {
        try
        {
            await _next(context);
        }
        catch (PostgresException ex)
        {
            var (statusCode, body) = ApiErrorMapper.Map(ex);

            if (statusCode >= 500)
            {
                _logger.LogError(ex,
                    "Unmapped PostgresException: SqlState={SqlState} MessageText={MessageText}",
                    ex.SqlState, ex.MessageText);
            }
            else
            {
                _logger.LogWarning(
                    "PostgresException mapped to {StatusCode}: SqlState={SqlState} MessageText={MessageText}",
                    statusCode, ex.SqlState, ex.MessageText);
            }

            if (context.Response.HasStarted)
            {
                throw;
            }

            await TryLogExceptionAsync(context, dataSource, ex, statusCode);

            context.Response.Clear();
            context.Response.StatusCode = statusCode;
            context.Response.ContentType = "application/json";
            await JsonSerializer.SerializeAsync(context.Response.Body, body, _jsonOptions, context.RequestAborted);
        }
    }

    // Best-effort observability write of the exception trace to the control-plane
    // exception_log. Uses a FRESH connection from the data source — the request's
    // own connection/transaction is aborted by this point, so any command on it
    // would fail. The whole write is swallowed on failure: persisting the trace
    // must never replace the HTTP error response the client is owed.
    private async Task TryLogExceptionAsync(
        HttpContext context,
        NpgsqlDataSource dataSource,
        PostgresException ex,
        int statusCode)
    {
        try
        {
            var tenantId = context.TryGetTenant()?.Id;

            var userIdClaim = context.User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
                              ?? context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            Guid? userId = Guid.TryParse(userIdClaim, out var parsedUserId) ? parsedUserId : null;

            await using var connection = await dataSource.OpenConnectionAsync(context.RequestAborted);
            await using var command = new NpgsqlCommand(
                "SELECT system_api.log_exception(" +
                "@pg_code, @message, @constraint_name, @detail, " +
                "@http_method, @path, @http_status, @tenant_id, @user_id)",
                connection);

            command.Parameters.Add(new NpgsqlParameter("pg_code", NpgsqlDbType.Text) { Value = ex.SqlState });
            command.Parameters.Add(new NpgsqlParameter("message", NpgsqlDbType.Text) { Value = ex.MessageText });
            command.Parameters.Add(new NpgsqlParameter("constraint_name", NpgsqlDbType.Text)
                { Value = (object?)ex.ConstraintName ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter("detail", NpgsqlDbType.Text)
                { Value = (object?)ex.Detail ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter("http_method", NpgsqlDbType.Text)
                { Value = context.Request.Method });
            command.Parameters.Add(new NpgsqlParameter("path", NpgsqlDbType.Text)
                { Value = context.Request.Path.Value ?? string.Empty });
            command.Parameters.Add(new NpgsqlParameter("http_status", NpgsqlDbType.Integer) { Value = statusCode });
            command.Parameters.Add(new NpgsqlParameter("tenant_id", NpgsqlDbType.Uuid)
                { Value = (object?)tenantId ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter("user_id", NpgsqlDbType.Uuid)
                { Value = (object?)userId ?? DBNull.Value });

            await command.ExecuteNonQueryAsync(context.RequestAborted);
        }
        catch (Exception logEx)
        {
            _logger.LogError(logEx,
                "Failed to persist exception trace to exception_log: SqlState={SqlState}",
                ex.SqlState);
        }
    }
}
