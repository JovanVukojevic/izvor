using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using FluentAssertions;
using Izvor.Api.Models;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Microsoft.AspNetCore.Mvc.Testing;
using Npgsql;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class RefreshTokenEndpointTests : IAsyncLifetime
{
    private const string AcmeBaseUri = "http://acme.izvor.lvh.me";
    private const string IntellyaBaseUri = "http://intellya.izvor.lvh.me";

    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private readonly WebApplicationFactoryClientOptions _noCookieJar = new()
    {
        AllowAutoRedirect = false,
        HandleCookies = false
    };

    public RefreshTokenEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync() =>
        await TestSeed.ResetRefreshTokensAsync(_postgres.AdminConnectionString);

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient CreateClient(string baseUri)
    {
        var client = _factory.CreateClient(_noCookieJar);
        client.BaseAddress = new Uri(baseUri);
        return client;
    }

    private static async Task<(AuthResponse Body, string CookieValue, string SetCookieHeader)> LoginAsync(
        HttpClient client, string email, string password)
    {
        var response = await client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email, password));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
        var setCookie = ExtractRefreshSetCookie(response);
        var cookieValue = ExtractCookieValue(setCookie);
        return (body, cookieValue, setCookie);
    }

    private static string ExtractRefreshSetCookie(HttpResponseMessage response)
    {
        response.Headers.TryGetValues("Set-Cookie", out var values).Should().BeTrue(
            "the response should carry a Set-Cookie header");
        var cookie = values!.SingleOrDefault(v => v.StartsWith("refreshToken=", StringComparison.Ordinal));
        cookie.Should().NotBeNull("a refreshToken cookie should be present");
        return cookie!;
    }

    private static string? TryExtractRefreshSetCookie(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("Set-Cookie", out var values))
        {
            return null;
        }
        return values.SingleOrDefault(v => v.StartsWith("refreshToken=", StringComparison.Ordinal));
    }

    private static string ExtractCookieValue(string setCookieHeader)
    {
        var match = Regex.Match(setCookieHeader, @"^refreshToken=([^;]*)");
        match.Success.Should().BeTrue();
        return match.Groups[1].Value;
    }

    private static string Sha256Hex(string input) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input))).ToLowerInvariant();

    private async Task<int> CountTokensAsync(Guid tenantId, string? whereExtra = null)
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
            $"SELECT count(*) FROM impl.refresh_tokens {whereExtra ?? string.Empty}", conn, tx);
        var raw = (long)(await cmd.ExecuteScalarAsync())!;
        return (int)raw;
    }

    private async Task<bool> IsTokenRevokedAsync(string tokenPlaintext, Guid? tenantId = null)
    {
        var hash = Sha256Hex(tokenPlaintext);
        var scopedTenant = tenantId ?? TestIds.AcmeTenantId;
        await using var conn = new NpgsqlConnection(_postgres.AdminConnectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using (var setCfg = new NpgsqlCommand(
            "SELECT set_config('app.current_tenant', @t, true)", conn, tx))
        {
            setCfg.Parameters.AddWithValue("t", scopedTenant.ToString());
            await setCfg.ExecuteNonQueryAsync();
        }
        await using var cmd = new NpgsqlCommand(
            "SELECT revoked_at IS NOT NULL FROM impl.refresh_tokens WHERE token_hash = @h", conn, tx);
        cmd.Parameters.AddWithValue("h", hash);
        var result = await cmd.ExecuteScalarAsync();
        return result is bool b && b;
    }

    private async Task InsertExpiredTokenAsync(Guid tenantId, Guid userId, string tokenPlaintext)
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
            "VALUES (@t, @u, @h, NOW() - INTERVAL '8 days', NOW() - INTERVAL '1 hour')",
            conn, tx);
        cmd.Parameters.AddWithValue("t", tenantId);
        cmd.Parameters.AddWithValue("u", userId);
        cmd.Parameters.AddWithValue("h", hash);
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
    }

    [Fact]
    public async Task R1_login_sets_refresh_cookie_with_expected_attributes()
    {
        var client = CreateClient(AcmeBaseUri);
        var (_, cookieValue, setCookie) = await LoginAsync(client, TestIds.MarkoEmail, TestIds.TestPassword);

        cookieValue.Should().NotBeNullOrEmpty();
        cookieValue.Length.Should().Be(43, "raw refresh token is 256 bits as URL-safe base64 without padding");

        setCookie.Should().Contain("path=/api/auth");
        setCookie.Should().Contain("samesite=lax", "Lax balances CSRF protection with same-site refresh flow");
        setCookie.ToLowerInvariant().Should().Contain("httponly");
        setCookie.ToLowerInvariant().Should().NotContain("secure", "test server runs over HTTP");
        setCookie.ToLowerInvariant().Should().Contain("expires=");
    }

    [Fact]
    public async Task R2_refresh_with_valid_cookie_rotates_and_returns_new_access()
    {
        var client = CreateClient(AcmeBaseUri);
        var (loginBody, oldToken, _) = await LoginAsync(client, TestIds.MarkoEmail, TestIds.TestPassword);

        var refreshRequest = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        refreshRequest.Headers.Add("Cookie", $"refreshToken={oldToken}");
        var response = await client.SendAsync(refreshRequest);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<AuthResponse>();
        body!.AccessToken.Should().NotBeNullOrEmpty();
        body.AccessToken.Should().NotBe(loginBody.AccessToken, "rotation must mint a fresh access token");
        body.User.Email.Should().Be(TestIds.MarkoEmail);
        body.User.Tenant.Subdomain.Should().Be(TestIds.AcmeSubdomain);

        var newCookie = ExtractRefreshSetCookie(response);
        var newToken = ExtractCookieValue(newCookie);
        newToken.Should().NotBe(oldToken);

        (await IsTokenRevokedAsync(oldToken)).Should().BeTrue("old token must be revoked after rotation");
        (await IsTokenRevokedAsync(newToken)).Should().BeFalse("new token must be active");
    }

    [Fact]
    public async Task R3_refresh_with_missing_cookie_returns_401()
    {
        var client = CreateClient(AcmeBaseUri);
        var response = await client.PostAsync("/api/auth/refresh", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("unauthorized");
        body.Message.Should().Be("missing_refresh_token");
    }

    [Fact]
    public async Task R4_refresh_with_invalid_cookie_returns_401_and_clears_cookie()
    {
        var client = CreateClient(AcmeBaseUri);
        var bogus = new string('x', 43);
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        request.Headers.Add("Cookie", $"refreshToken={bogus}");
        var response = await client.SendAsync(request);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("unauthorized");
        body.Message.Should().Be("invalid_refresh_token");

        var setCookie = TryExtractRefreshSetCookie(response);
        setCookie.Should().NotBeNull("clearing cookie should be appended on rejection");
        setCookie!.Should().Contain("expires=Thu, 01 Jan 1970", "Unix epoch marks immediate expiry");
    }

    [Fact]
    public async Task R5_refresh_with_expired_cookie_returns_401()
    {
        const string Plain = "expired-token-fixture-value-43-characters-x";
        await InsertExpiredTokenAsync(TestIds.AcmeTenantId, TestIds.MarkoUserId, Plain);

        var client = CreateClient(AcmeBaseUri);
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        request.Headers.Add("Cookie", $"refreshToken={Plain}");
        var response = await client.SendAsync(request);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("invalid_refresh_token");
    }

    [Fact]
    public async Task R6_refresh_with_already_rotated_cookie_returns_401()
    {
        var client = CreateClient(AcmeBaseUri);
        var (_, originalToken, _) = await LoginAsync(client, TestIds.MarkoEmail, TestIds.TestPassword);

        var first = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        first.Headers.Add("Cookie", $"refreshToken={originalToken}");
        var firstResp = await client.SendAsync(first);
        firstResp.StatusCode.Should().Be(HttpStatusCode.OK);

        var replay = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        replay.Headers.Add("Cookie", $"refreshToken={originalToken}");
        var replayResp = await client.SendAsync(replay);

        replayResp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var body = await replayResp.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("invalid_refresh_token");
    }

    [Fact]
    public async Task R7_logout_with_valid_cookie_revokes_and_clears_cookie()
    {
        var client = CreateClient(AcmeBaseUri);
        var (_, token, _) = await LoginAsync(client, TestIds.MarkoEmail, TestIds.TestPassword);

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout");
        request.Headers.Add("Cookie", $"refreshToken={token}");
        var response = await client.SendAsync(request);

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var setCookie = ExtractRefreshSetCookie(response);
        setCookie.Should().Contain("expires=Thu, 01 Jan 1970");

        (await IsTokenRevokedAsync(token)).Should().BeTrue();
    }

    [Fact]
    public async Task R8_logout_without_cookie_returns_204_and_clears_cookie()
    {
        var client = CreateClient(AcmeBaseUri);
        var response = await client.PostAsync("/api/auth/logout", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
        var setCookie = ExtractRefreshSetCookie(response);
        setCookie.Should().Contain("expires=Thu, 01 Jan 1970");
    }

    [Fact]
    public async Task R9_cross_tenant_refresh_attack_returns_401()
    {
        var acmeClient = CreateClient(AcmeBaseUri);
        var (_, acmeToken, _) = await LoginAsync(acmeClient, TestIds.MarkoEmail, TestIds.TestPassword);

        var intellyaClient = CreateClient(IntellyaBaseUri);
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        request.Headers.Add("Cookie", $"refreshToken={acmeToken}");
        var response = await intellyaClient.SendAsync(request);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("invalid_refresh_token", "RLS hides the row under the wrong tenant");

        (await IsTokenRevokedAsync(acmeToken)).Should().BeFalse(
            "cross-tenant lookup must not touch the legitimate tenant's row");
    }

    [Fact]
    public async Task R10_refresh_burst_hits_rate_limit()
    {
        var client = CreateClient(AcmeBaseUri);

        HttpStatusCode? rateLimitedAt = null;
        for (var i = 1; i <= 11; i++)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
            request.Headers.Add("Cookie", "refreshToken=does-not-matter-any-bogus-value-43chars");
            var response = await client.SendAsync(request);

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rateLimitedAt = response.StatusCode;
                break;
            }
        }

        rateLimitedAt.Should().Be(HttpStatusCode.TooManyRequests,
            "the 11th request within 60s should be rejected by the refresh rate-limit policy");
    }
}
