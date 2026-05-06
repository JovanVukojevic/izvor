using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Models;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Microsoft.AspNetCore.Mvc.Testing;
using Npgsql;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class UsersEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private readonly WebApplicationFactoryClientOptions _noCookieJar = new()
    {
        AllowAutoRedirect = false,
        HandleCookies = false
    };

    public UsersEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync() =>
        await TestSeed.ResetUsersAsync(_postgres.AdminConnectionString);

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient MarkoClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.MarkoUserId, "admin", TestIds.MarkoEmail, TestIds.AcmeTenantId);
    private HttpClient PeraClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.PeraUserId, "learner", TestIds.PeraEmail, TestIds.AcmeTenantId);
    private HttpClient JanaClient() => MakeClient(TestIds.IntellyaSubdomain, TestIds.JanaUserId, "admin", TestIds.JanaEmail, TestIds.IntellyaTenantId);

    private HttpClient MakeClient(string subdomain, Guid userId, string role, string email, Guid tenantId) =>
        _factory.CreateClient()
            .WithTenant(subdomain)
            .WithBearer(AuthHelper.MintToken(_factory.Services, userId, tenantId, role, email));

    private HttpClient AnonymousClient(string subdomain) =>
        _factory.CreateClient(_noCookieJar).WithTenant(subdomain);

    [Fact] // U1
    public async Task List_as_admin_returns_all_users_in_tenant()
    {
        var marko = MarkoClient();
        var response = await marko.GetAsync("/api/users");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<UserResponse>>();
        list!.Select(u => u.Id).Should().BeEquivalentTo(new[]
        {
            TestIds.MarkoUserId,
            TestIds.AnaUserId,
            TestIds.PeraUserId,
            TestIds.IvanaUserId,
            TestIds.InactiveUserId
        });
        list!.Single(u => u.Id == TestIds.InactiveUserId).IsActive.Should().BeFalse();
        list!.Single(u => u.Id == TestIds.MarkoUserId).IsActive.Should().BeTrue();
    }

    [Fact] // U2
    public async Task List_with_role_filter_returns_only_learners()
    {
        var marko = MarkoClient();
        var response = await marko.GetAsync("/api/users?role=learner");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<UserResponse>>();
        list!.Select(u => u.Id).Should().BeEquivalentTo(new[]
        {
            TestIds.PeraUserId,
            TestIds.IvanaUserId,
            TestIds.InactiveUserId
        });
        list.Should().OnlyContain(u => u.Role == "learner");
    }

    [Fact] // U3
    public async Task List_as_learner_returns_403()
    {
        var pera = PeraClient();
        var response = await pera.GetAsync("/api/users");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Contain("admin required");
    }

    [Fact] // U4
    public async Task Get_as_admin_returns_user()
    {
        var marko = MarkoClient();
        var response = await marko.GetAsync($"/api/users/{TestIds.AnaUserId}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<UserResponse>();
        body!.Id.Should().Be(TestIds.AnaUserId);
        body.Email.Should().Be(TestIds.AnaEmail);
        body.Role.Should().Be("author");
        body.IsActive.Should().BeTrue();
    }

    [Fact] // U5
    public async Task Get_unknown_id_returns_404_user_not_found()
    {
        var marko = MarkoClient();
        var response = await marko.GetAsync($"/api/users/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
        body.Message.Should().Be("user_not_found");
    }

    [Fact] // U6 — layered defense: JwtTenantMatchMiddleware fires before mapper
    public async Task Get_cross_tenant_user_returns_403_tenant_mismatch()
    {
        var crossTenantClient = _factory.CreateClient()
            .WithTenant(TestIds.IntellyaSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.MarkoUserId, TestIds.AcmeTenantId, "admin", TestIds.MarkoEmail));

        var response = await crossTenantClient.GetAsync($"/api/users/{TestIds.JanaUserId}");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("tenant_mismatch");
    }

    [Fact] // U7
    public async Task Create_as_admin_returns_201_with_location_and_body()
    {
        var marko = MarkoClient();
        var request = new CreateUserRequest("newuser@acme.test", "passw0rd!", "learner");
        var response = await marko.PostAsJsonAsync("/api/users", request);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        var body = await response.Content.ReadFromJsonAsync<UserResponse>();
        body!.Email.Should().Be("newuser@acme.test");
        body.Role.Should().Be("learner");
        body.IsActive.Should().BeTrue();
        response.Headers.Location!.ToString().Should().EndWith($"/api/users/{body.Id}");
    }

    [Fact] // U8
    public async Task Create_duplicate_email_returns_409_already_exists()
    {
        var marko = MarkoClient();
        var request = new CreateUserRequest(TestIds.AnaEmail, "passw0rd!", "learner");
        var response = await marko.PostAsJsonAsync("/api/users", request);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("already_exists");
    }

    [Fact] // U9
    public async Task Create_invalid_role_returns_400_validation_failed()
    {
        var marko = MarkoClient();
        var request = new CreateUserRequest("wizard@acme.test", "passw0rd!", "wizard");
        var response = await marko.PostAsJsonAsync("/api/users", request);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    [Fact] // U10 — verifies the new cross-cutting invariant from migration 019
    public async Task Deactivate_as_admin_returns_204_and_revokes_refresh_tokens()
    {
        await InsertRefreshTokenAsync(TestIds.AcmeTenantId, TestIds.AnaUserId, "ana-token-fixture-value-43-chars-padding-x");
        await InsertRefreshTokenAsync(TestIds.AcmeTenantId, TestIds.AnaUserId, "ana-token-fixture-value-43-chars-padding-y");

        var marko = MarkoClient();
        var response = await marko.PostAsync($"/api/users/{TestIds.AnaUserId}/deactivate", content: null);
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var revokedCount = await CountRevokedTokensForUserAsync(TestIds.AcmeTenantId, TestIds.AnaUserId);
        var totalCount = await CountTokensForUserAsync(TestIds.AcmeTenantId, TestIds.AnaUserId);
        revokedCount.Should().Be(2);
        totalCount.Should().Be(2);
    }

    [Fact] // U11
    public async Task Deactivate_self_returns_403_cannot_deactivate_self()
    {
        var marko = MarkoClient();
        var response = await marko.PostAsync($"/api/users/{TestIds.MarkoUserId}/deactivate", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Be("cannot_deactivate_self");
    }

    [Fact] // U12
    public async Task Activate_already_active_returns_204_idempotent()
    {
        var marko = MarkoClient();
        var response = await marko.PostAsync($"/api/users/{TestIds.AnaUserId}/activate", content: null);
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // U13 — verifies invariant from migration 019: reset_password also revokes
    public async Task Reset_password_as_admin_returns_204_and_revokes_tokens_and_changes_password()
    {
        await InsertRefreshTokenAsync(TestIds.AcmeTenantId, TestIds.PeraUserId, "pera-token-fixture-value-43-chars-padding-x");

        var marko = MarkoClient();
        var resetResponse = await marko.PostAsJsonAsync(
            $"/api/users/{TestIds.PeraUserId}/reset-password",
            new AdminResetPasswordRequest("newpassword123"));
        resetResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var revoked = await CountRevokedTokensForUserAsync(TestIds.AcmeTenantId, TestIds.PeraUserId);
        revoked.Should().Be(1, "admin_reset_password must revoke all of the target user's refresh tokens");

        var anon = AnonymousClient(TestIds.AcmeSubdomain);

        var oldPasswordLogin = await anon.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(TestIds.PeraEmail, TestIds.TestPassword));
        oldPasswordLogin.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var newPasswordLogin = await anon.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(TestIds.PeraEmail, "newpassword123"));
        newPasswordLogin.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact] // U14
    public async Task Reset_password_short_password_returns_400_validation_failed()
    {
        var marko = MarkoClient();
        var response = await marko.PostAsJsonAsync(
            $"/api/users/{TestIds.AnaUserId}/reset-password",
            new AdminResetPasswordRequest("abc"));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    [Fact] // U15 — admin_reset_password filters on is_active = true → user_not_found
    public async Task Reset_password_inactive_user_returns_404_user_not_found()
    {
        var marko = MarkoClient();
        var response = await marko.PostAsJsonAsync(
            $"/api/users/{TestIds.InactiveUserId}/reset-password",
            new AdminResetPasswordRequest("newpassword123"));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
        body.Message.Should().Be("user_not_found");
    }

    [Fact] // U16
    public async Task Reset_password_as_learner_returns_403()
    {
        var pera = PeraClient();
        var response = await pera.PostAsJsonAsync(
            $"/api/users/{TestIds.AnaUserId}/reset-password",
            new AdminResetPasswordRequest("newpassword123"));

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Contain("admin required");
    }

    private static string Sha256Hex(string input) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input))).ToLowerInvariant();

    private async Task InsertRefreshTokenAsync(Guid tenantId, Guid userId, string tokenPlaintext)
    {
        var hash = Sha256Hex(tokenPlaintext);
        await using var conn = new NpgsqlConnection(_postgres.AdminConnectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using (var setCfg = new NpgsqlCommand("SELECT set_config('app.current_tenant', @t, true)", conn, tx))
        {
            setCfg.Parameters.AddWithValue("t", tenantId.ToString());
            await setCfg.ExecuteNonQueryAsync();
        }
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO impl.refresh_tokens (tenant_id, user_id, token_hash, issued_at, expires_at) " +
            "VALUES (@t, @u, @h, NOW(), NOW() + INTERVAL '7 days')",
            conn, tx);
        cmd.Parameters.AddWithValue("t", tenantId);
        cmd.Parameters.AddWithValue("u", userId);
        cmd.Parameters.AddWithValue("h", hash);
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
    }

    private async Task<int> CountRevokedTokensForUserAsync(Guid tenantId, Guid userId) =>
        await CountTokensWhereAsync(tenantId, userId, "AND revoked_at IS NOT NULL");

    private async Task<int> CountTokensForUserAsync(Guid tenantId, Guid userId) =>
        await CountTokensWhereAsync(tenantId, userId, string.Empty);

    private async Task<int> CountTokensWhereAsync(Guid tenantId, Guid userId, string extraWhere)
    {
        await using var conn = new NpgsqlConnection(_postgres.AdminConnectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using (var setCfg = new NpgsqlCommand("SELECT set_config('app.current_tenant', @t, true)", conn, tx))
        {
            setCfg.Parameters.AddWithValue("t", tenantId.ToString());
            await setCfg.ExecuteNonQueryAsync();
        }
        await using var cmd = new NpgsqlCommand(
            $"SELECT count(*) FROM impl.refresh_tokens WHERE user_id = @u {extraWhere}", conn, tx);
        cmd.Parameters.AddWithValue("u", userId);
        var raw = (long)(await cmd.ExecuteScalarAsync())!;
        return (int)raw;
    }
}
