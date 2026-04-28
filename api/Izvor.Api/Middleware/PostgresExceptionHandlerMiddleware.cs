using System.Text.Json;
using Izvor.Api.Errors;
using Npgsql;

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

    public async Task InvokeAsync(HttpContext context)
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

            context.Response.Clear();
            context.Response.StatusCode = statusCode;
            context.Response.ContentType = "application/json";
            await JsonSerializer.SerializeAsync(context.Response.Body, body, _jsonOptions, context.RequestAborted);
        }
    }
}
