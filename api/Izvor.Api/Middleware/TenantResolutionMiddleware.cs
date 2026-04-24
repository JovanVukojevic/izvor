using System.Text.Json;
using Izvor.Api.Configuration;
using Izvor.Api.Extensions;
using Izvor.Api.Models;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Izvor.Api.Middleware;

public sealed class TenantResolutionMiddleware
{
    private static readonly string[] WhitelistedPrefixes =
    {
        "/api/health",
        "/openapi",
        "/scalar"
    };

    private static readonly HashSet<string> ReservedSubdomains = new(StringComparer.OrdinalIgnoreCase)
    {
        "www",
        "admin",
        "api"
    };

    private readonly RequestDelegate _next;
    private readonly string _baseDomain;
    private readonly ILogger<TenantResolutionMiddleware> _logger;
    private readonly JsonSerializerOptions _jsonOptions;

    public TenantResolutionMiddleware(
        RequestDelegate next,
        IOptions<TenantHostSettings> hostSettings,
        ILogger<TenantResolutionMiddleware> logger,
        JsonSerializerOptions jsonOptions)
    {
        _next = next;
        _baseDomain = hostSettings.Value.BaseDomain;
        _logger = logger;
        _jsonOptions = jsonOptions;
    }

    public async Task InvokeAsync(HttpContext context, NpgsqlDataSource dataSource)
    {
        if (IsWhitelisted(context.Request.Path))
        {
            await _next(context);
            return;
        }

        var host = context.Request.Host.Host;
        var subdomain = ExtractSubdomain(host);

        if (subdomain is null)
        {
            await WriteErrorAsync(context, 400, "invalid_host",
                $"Host '{host}' does not match expected pattern '*.{_baseDomain}'");
            return;
        }

        if (ReservedSubdomains.Contains(subdomain))
        {
            await WriteErrorAsync(context, 400, "invalid_host",
                $"Subdomain '{subdomain}' is reserved");
            return;
        }

        var tenant = await LookupTenantAsync(dataSource, subdomain, context.RequestAborted);

        if (tenant is null)
        {
            await WriteErrorAsync(context, 404, "tenant_not_found",
                $"No tenant configured for subdomain '{subdomain}'");
            return;
        }

        if (!string.Equals(tenant.Status, "active", StringComparison.OrdinalIgnoreCase))
        {
            await WriteErrorAsync(context, 403, "tenant_suspended",
                $"Tenant '{tenant.Subdomain}' is currently {tenant.Status}");
            return;
        }

        context.SetTenant(tenant);
        await _next(context);
    }

    private static bool IsWhitelisted(PathString path)
    {
        foreach (var prefix in WhitelistedPrefixes)
        {
            if (path.StartsWithSegments(prefix))
            {
                return true;
            }
        }
        return false;
    }

    private string? ExtractSubdomain(string host)
    {
        var suffix = "." + _baseDomain;
        if (!host.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var subdomain = host.Substring(0, host.Length - suffix.Length);
        if (string.IsNullOrWhiteSpace(subdomain) || subdomain.Contains('.'))
        {
            return null;
        }

        return subdomain.ToLowerInvariant();
    }

    private static async Task<Tenant?> LookupTenantAsync(
        NpgsqlDataSource dataSource,
        string subdomain,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT id, name, code, subdomain, status, created_at, updated_at " +
            "FROM system_api.get_tenant_by_subdomain(@subdomain)",
            connection);
        command.Parameters.AddWithValue("subdomain", subdomain);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new Tenant(
            Id: reader.GetGuid(0),
            Name: reader.GetString(1),
            Code: reader.GetString(2),
            Subdomain: reader.GetString(3),
            Status: reader.GetString(4),
            CreatedAt: reader.GetDateTime(5),
            UpdatedAt: reader.GetDateTime(6));
    }

    private async Task WriteErrorAsync(
        HttpContext context,
        int statusCode,
        string error,
        string message)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        var payload = new ErrorResponse(error, message);
        await JsonSerializer.SerializeAsync(context.Response.Body, payload, _jsonOptions);
    }
}
