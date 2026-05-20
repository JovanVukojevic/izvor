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
public sealed class CategoriesEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;

    public CategoriesEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync() =>
        await TestSeed.ResetCategoriesAndCoursesAsync(_postgres.AdminConnectionString);

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

    [Fact] // C1
    public async Task Admin_can_create_category()
    {
        var client = AdminClient();
        var response = await client.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("Programming", "All things code"));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        var body = await response.Content.ReadFromJsonAsync<CategoryResponse>();
        body!.Name.Should().Be("Programming");
        body.Description.Should().Be("All things code");
        body.Id.Should().NotBe(Guid.Empty);
    }

    [Fact] // C2
    public async Task Learner_create_category_is_forbidden()
    {
        var client = LearnerClient();
        var response = await client.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("X", null));

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
    }

    [Fact] // C3
    public async Task List_returns_created_categories()
    {
        var admin = AdminClient();
        await admin.PostAsJsonAsync("/api/categories", new CreateCategoryRequest("A", null));
        await admin.PostAsJsonAsync("/api/categories", new CreateCategoryRequest("B", null));

        var response = await admin.GetAsync("/api/categories");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<CategoryResponse>>();
        list.Should().HaveCount(2);
        list!.Select(c => c.Name).Should().BeEquivalentTo(new[] { "A", "B" });
    }

    [Fact] // C4
    public async Task Get_by_id_returns_match()
    {
        var admin = AdminClient();
        var created = await CreateCategoryAsync(admin, "Get-test");
        var response = await admin.GetAsync($"/api/categories/{created.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<CategoryResponse>();
        body!.Id.Should().Be(created.Id);
        body.Name.Should().Be("Get-test");
    }

    [Fact] // C5
    public async Task Admin_can_update_category()
    {
        var admin = AdminClient();
        var created = await CreateCategoryAsync(admin, "Original");
        var update = await admin.PutAsJsonAsync($"/api/categories/{created.Id}",
            new UpdateCategoryRequest("Renamed", "Updated desc"));
        update.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await admin.GetAsync($"/api/categories/{created.Id}");
        var body = await get.Content.ReadFromJsonAsync<CategoryResponse>();
        body!.Name.Should().Be("Renamed");
        body.Description.Should().Be("Updated desc");
    }

    [Fact] // C6
    public async Task Update_non_existent_returns_404()
    {
        var admin = AdminClient();
        var response = await admin.PutAsJsonAsync($"/api/categories/{Guid.NewGuid()}",
            new UpdateCategoryRequest("Whatever", null));
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
    }

    [Fact] // C7
    public async Task Admin_can_delete_unused_category()
    {
        var admin = AdminClient();
        var created = await CreateCategoryAsync(admin, "Disposable");

        var del = await admin.DeleteAsync($"/api/categories/{created.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await admin.GetAsync($"/api/categories/{created.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact] // C8
    public async Task Delete_category_referenced_by_course_returns_409()
    {
        var admin = AdminClient();
        var category = await CreateCategoryAsync(admin, "Referenced");

        var ana = _factory.CreateClient()
            .WithTenant(TestIds.AcmeSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.AnaUserId, TestIds.AcmeTenantId, "author", TestIds.AnaEmail));
        var courseResponse = await ana.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Course1", null, category.Id));
        courseResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var del = await admin.DeleteAsync($"/api/categories/{category.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await del.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("constraint_violation");
    }

    [Fact] // C9
    public async Task Cross_tenant_jwt_mismatch_is_forbidden()
    {
        var client = _factory.CreateClient()
            .WithTenant(TestIds.IntellyaSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.MarkoUserId, TestIds.AcmeTenantId, "admin", TestIds.MarkoEmail));

        var response = await client.GetAsync("/api/categories");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("tenant_mismatch");
    }

    [Fact] // C10
    public async Task Cross_tenant_via_two_tenants_returns_404_for_other_tenants_id()
    {
        var marko = AdminClient();
        var acmeCategory = await CreateCategoryAsync(marko, "AcmeOnly");

        var jana = _factory.CreateClient()
            .WithTenant(TestIds.IntellyaSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.JanaUserId, TestIds.IntellyaTenantId, "admin", TestIds.JanaEmail));

        var response = await jana.GetAsync($"/api/categories/{acmeCategory.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact] // C11
    public async Task Create_with_duplicate_name_case_insensitive_returns_409()
    {
        var admin = AdminClient();
        await admin.PostAsJsonAsync("/api/categories", new CreateCategoryRequest("Lang", null));

        var response = await admin.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("LANG", null));
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("already_exists");
    }

    private static async Task<CategoryResponse> CreateCategoryAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest(name, null));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<CategoryResponse>())!;
    }
}
