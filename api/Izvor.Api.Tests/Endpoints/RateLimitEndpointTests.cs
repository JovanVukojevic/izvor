using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class RateLimitEndpointTests : IAsyncLifetime
{
    private const string AcmeBaseUri = "http://acme.izvor.lvh.me";

    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private readonly WebApplicationFactoryClientOptions _clientOptions = new()
    {
        AllowAutoRedirect = false,
        HandleCookies = false
    };

    public RateLimitEndpointTests(PostgresFixture postgres)
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
        var client = _factory.CreateClient(_clientOptions);
        client.BaseAddress = new Uri(baseUri);
        return client;
    }

    private static HttpRequestMessage BuildLogin(string email, string clientIp)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/login")
        {
            Content = JsonContent.Create(new LoginRequest(email, "wrong-password"))
        };
        request.Headers.Add(IzvorWebApplicationFactory.TestClientIpHeader, clientIp);
        return request;
    }

    [Fact] // RL1
    public async Task Login_per_user_limit_fires_with_distinct_ips()
    {
        var client = CreateClient(AcmeBaseUri);
        const string email = TestIds.MarkoEmail;

        HttpStatusCode? rateLimitedAt = null;
        for (var i = 1; i <= 11; i++)
        {
            var clientIp = $"192.0.2.{i}";
            var response = await client.SendAsync(BuildLogin(email, clientIp));

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rateLimitedAt = response.StatusCode;
                rateLimitedAt.Should().Be(HttpStatusCode.TooManyRequests);
                i.Should().Be(11, "per-user limit is 10/60s — only the 11th request should be rejected");
                var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
                body!.Error.Should().Be("rate_limit_exceeded");
                break;
            }

            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized,
                "wrong password for the first 10 attempts");
        }

        rateLimitedAt.Should().Be(HttpStatusCode.TooManyRequests,
            "11 attempts on the same email from distinct IPs must hit the per-user limit");
    }

    [Fact] // RL2
    public async Task Login_per_ip_limit_fires_with_same_ip_and_distinct_emails()
    {
        var client = CreateClient(AcmeBaseUri);
        const string clientIp = "192.0.2.100";

        HttpStatusCode? rateLimitedAt = null;
        for (var i = 1; i <= 6; i++)
        {
            var email = $"unique-user-{i}@acme.test";
            var response = await client.SendAsync(BuildLogin(email, clientIp));

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rateLimitedAt = response.StatusCode;
                i.Should().Be(6, "per-IP login limit is 5/60s — only the 6th request should be rejected");
                break;
            }

            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized,
                "wrong password / unknown email for the first 5 attempts");
        }

        rateLimitedAt.Should().Be(HttpStatusCode.TooManyRequests,
            "6 attempts from the same IP must hit the per-IP login limit even with distinct emails");
    }

    [Fact] // RL3
    public async Task Global_per_ip_limit_fires_on_arbitrary_endpoint()
    {
        var client = CreateClient(AcmeBaseUri);
        const string clientIp = "192.0.2.200";

        HttpStatusCode? rateLimitedAt = null;
        int? rejectedAt = null;
        for (var i = 1; i <= 101; i++)
        {
            var request = new HttpRequestMessage(HttpMethod.Get, "/api/health");
            request.Headers.Add(IzvorWebApplicationFactory.TestClientIpHeader, clientIp);
            var response = await client.SendAsync(request);

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rateLimitedAt = response.StatusCode;
                rejectedAt = i;
                break;
            }

            response.StatusCode.Should().Be(HttpStatusCode.OK,
                $"request {i}/101 to /api/health should succeed under the global cap");
        }

        rateLimitedAt.Should().Be(HttpStatusCode.TooManyRequests,
            "101 requests from the same IP must hit the universal global limit");
        rejectedAt.Should().Be(101, "global per-IP cap is 100/60s — only the 101st request should be rejected");
    }
}
