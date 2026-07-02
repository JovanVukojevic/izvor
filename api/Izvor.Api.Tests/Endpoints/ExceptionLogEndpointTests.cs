using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Npgsql;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class ExceptionLogEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;

    public ExceptionLogEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync()
    {
        await using var conn = new NpgsqlConnection(_postgres.AdminConnectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("DELETE FROM system_impl.exception_log", conn);
        await cmd.ExecuteNonQueryAsync();
    }

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient AdminClient() =>
        _factory.CreateClient()
            .WithTenant(TestIds.AcmeSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.MarkoUserId, TestIds.AcmeTenantId, "admin", TestIds.MarkoEmail));

    private HttpClient LearnerClient() =>
        _factory.CreateClient()
            .WithTenant(TestIds.AcmeSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.PeraUserId, TestIds.AcmeTenantId, "learner", TestIds.PeraEmail));

    [Fact] // XL1
    public async Task Forbidden_action_writes_exception_log_row()
    {
        var client = LearnerClient();
        var response = await client.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("Programming", null));

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        var row = await QuerySingleRowAsync("/api/categories", 403);
        row.Should().NotBeNull();
        row!.HttpMethod.Should().Be("POST");
        row.PgCode.Should().NotBeNullOrEmpty();
        row.Message.Should().Contain("role");
        row.TenantId.Should().Be(TestIds.AcmeTenantId);
        row.UserId.Should().Be(TestIds.PeraUserId);
    }

    [Fact] // XL2
    public async Task Not_found_action_writes_exception_log_row()
    {
        var client = AdminClient();
        var unknownId = Guid.NewGuid();
        var response = await client.PutAsJsonAsync($"/api/categories/{unknownId}",
            new UpdateCategoryRequest("Renamed", null));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);

        var row = await QuerySingleRowAsync($"/api/categories/{unknownId}", 404);
        row.Should().NotBeNull();
        row!.HttpMethod.Should().Be("PUT");
        row.Message.Should().Be("category_not_found");
        row.TenantId.Should().Be(TestIds.AcmeTenantId);
        row.UserId.Should().Be(TestIds.MarkoUserId);
    }

    private async Task<ExceptionLogRow?> QuerySingleRowAsync(string path, int httpStatus)
    {
        await using var conn = new NpgsqlConnection(_postgres.AdminConnectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand(
            "SELECT pg_code, message, http_method, http_status, path, tenant_id, user_id " +
            "FROM system_impl.exception_log WHERE path = @path AND http_status = @status",
            conn);
        cmd.Parameters.AddWithValue("path", path);
        cmd.Parameters.AddWithValue("status", httpStatus);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return null;
        }

        var row = new ExceptionLogRow(
            PgCode: reader.GetString(0),
            Message: reader.GetString(1),
            HttpMethod: reader.GetString(2),
            HttpStatus: reader.GetInt32(3),
            Path: reader.GetString(4),
            TenantId: reader.IsDBNull(5) ? null : reader.GetGuid(5),
            UserId: reader.IsDBNull(6) ? null : reader.GetGuid(6));

        (await reader.ReadAsync()).Should().BeFalse("exactly one exception_log row should match");
        return row;
    }

    private sealed record ExceptionLogRow(
        string PgCode,
        string Message,
        string HttpMethod,
        int HttpStatus,
        string Path,
        Guid? TenantId,
        Guid? UserId);
}
