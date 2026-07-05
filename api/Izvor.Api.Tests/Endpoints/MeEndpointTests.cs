using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class MeEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;

    public MeEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient AdminClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.MarkoUserId, "admin", TestIds.MarkoEmail, TestIds.AcmeTenantId);

    private HttpClient MakeClient(string subdomain, Guid userId, string role, string email, Guid tenantId) =>
        _factory.CreateClient()
            .WithTenant(subdomain)
            .WithBearer(AuthHelper.MintToken(_factory.Services, userId, tenantId, role, email));

    [Fact] // M1
    public async Task Me_returns_current_user_with_tenant()
    {
        var admin = AdminClient();

        var response = await admin.GetAsync("/api/me");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<UserInfo>();
        body!.Id.Should().Be(TestIds.MarkoUserId);
        body.Email.Should().Be(TestIds.MarkoEmail);
        body.Role.Should().Be("admin");

        body.Tenant.Should().NotBeNull();
        body.Tenant.Id.Should().Be(TestIds.AcmeTenantId);
        body.Tenant.Name.Should().Be("Acme Corp");
        body.Tenant.Subdomain.Should().Be(TestIds.AcmeSubdomain);
    }

    [Fact] // M2
    public async Task Me_without_token_returns_401()
    {
        var client = _factory.CreateClient().WithTenant(TestIds.AcmeSubdomain);

        var response = await client.GetAsync("/api/me");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
