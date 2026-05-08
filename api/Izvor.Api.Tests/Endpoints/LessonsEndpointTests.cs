using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Models;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class LessonsEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private Guid _categoryId;
    private Guid _courseId;

    public LessonsEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync()
    {
        await TestSeed.ResetCategoriesAndCoursesAsync(_postgres.AdminConnectionString);

        var admin = AdminClient();
        var catResp = await admin.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("Default", null));
        catResp.EnsureSuccessStatusCode();
        _categoryId = (await catResp.Content.ReadFromJsonAsync<CategoryResponse>())!.Id;

        var courseResp = await AnaClient().PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Course1", null, _categoryId));
        courseResp.EnsureSuccessStatusCode();
        _courseId = (await courseResp.Content.ReadFromJsonAsync<CourseResponse>())!.Id;
    }

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient AdminClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.MarkoUserId, "admin", TestIds.MarkoEmail, TestIds.AcmeTenantId);
    private HttpClient AnaClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.AnaUserId, "author", TestIds.AnaEmail, TestIds.AcmeTenantId);
    private HttpClient PeraClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.PeraUserId, "learner", TestIds.PeraEmail, TestIds.AcmeTenantId);
    private HttpClient JanaClient() => MakeClient(TestIds.IntellyaSubdomain, TestIds.JanaUserId, "admin", TestIds.JanaEmail, TestIds.IntellyaTenantId);
    private HttpClient PetarClient() => MakeClient(TestIds.IntellyaSubdomain, TestIds.PetarUserId, "author", TestIds.PetarEmail, TestIds.IntellyaTenantId);

    private HttpClient MakeClient(string subdomain, Guid userId, string role, string email, Guid tenantId) =>
        _factory.CreateClient()
            .WithTenant(subdomain)
            .WithBearer(AuthHelper.MintToken(_factory.Services, userId, tenantId, role, email));

    [Fact] // L1
    public async Task Author_can_create_lesson_in_own_course()
    {
        var ana = AnaClient();
        var response = await ana.PostAsJsonAsync($"/api/courses/{_courseId}/lessons",
            new CreateLessonRequest("Intro", "Welcome to the course"));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var body = await response.Content.ReadFromJsonAsync<LessonResponse>();
        body!.Title.Should().Be("Intro");
        body.Content.Should().Be("Welcome to the course");
        body.Position.Should().Be(1);
        body.CourseId.Should().Be(_courseId);
        response.Headers.Location!.ToString().Should().Be($"/api/lessons/{body.Id}");
    }

    [Fact] // L2
    public async Task Admin_can_create_lesson_in_anyones_course()
    {
        var response = await AdminClient().PostAsJsonAsync($"/api/courses/{_courseId}/lessons",
            new CreateLessonRequest("AdminLesson", "Body"));
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }

    [Fact] // L3
    public async Task Learner_create_lesson_is_forbidden()
    {
        var response = await PeraClient().PostAsJsonAsync($"/api/courses/{_courseId}/lessons",
            new CreateLessonRequest("ShouldFail", "Body"));
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
    }

    [Fact] // L4
    public async Task Cross_tenant_create_returns_403_tenant_mismatch()
    {
        // Acme host + Intellya user JWT — JwtTenantMatchMiddleware fires before DB.
        var client = _factory.CreateClient()
            .WithTenant(TestIds.AcmeSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.PetarUserId, TestIds.IntellyaTenantId, "author", TestIds.PetarEmail));

        var response = await client.PostAsJsonAsync($"/api/courses/{_courseId}/lessons",
            new CreateLessonRequest("Hijack", "Body"));
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("tenant_mismatch");
    }

    [Fact] // L5
    public async Task List_returns_empty_for_course_with_no_lessons()
    {
        var response = await AnaClient().GetAsync($"/api/courses/{_courseId}/lessons");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<LessonResponse>>();
        list.Should().BeEmpty();
    }

    [Fact] // L6
    public async Task List_returns_lessons_in_position_order()
    {
        await CreateLessonAsync(AnaClient(), _courseId, "A", "a");
        await CreateLessonAsync(AnaClient(), _courseId, "B", "b");
        await CreateLessonAsync(AnaClient(), _courseId, "C", "c");

        var response = await AnaClient().GetAsync($"/api/courses/{_courseId}/lessons");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = (await response.Content.ReadFromJsonAsync<List<LessonResponse>>())!;
        list.Should().HaveCount(3);
        list[0].Title.Should().Be("A");
        list[0].Position.Should().Be(1);
        list[1].Title.Should().Be("B");
        list[1].Position.Should().Be(2);
        list[2].Title.Should().Be("C");
        list[2].Position.Should().Be(3);
    }

    [Fact] // L7
    public async Task Cross_tenant_list_returns_404_course_not_found()
    {
        // Intellya context queries an Acme course id; spec.list_lessons_by_course raises course_not_found.
        var response = await JanaClient().GetAsync($"/api/courses/{_courseId}/lessons");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
        body.Message.Should().Be("course_not_found");
    }

    [Fact] // L8
    public async Task Get_returns_lesson()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Get me", "body");
        var response = await AnaClient().GetAsync($"/api/lessons/{lesson.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<LessonResponse>();
        body!.Id.Should().Be(lesson.Id);
        body.Title.Should().Be("Get me");
    }

    [Fact] // L9
    public async Task Cross_tenant_get_returns_404_lesson_not_found()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Acme lesson", "body");

        var response = await JanaClient().GetAsync($"/api/lessons/{lesson.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("lesson_not_found");
    }

    [Fact] // L10
    public async Task Author_can_update_own_lesson_on_draft()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Old", "Old body");

        var update = await AnaClient().PutAsJsonAsync($"/api/lessons/{lesson.Id}",
            new UpdateLessonRequest("New", "New body"));
        update.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await AnaClient().GetAsync($"/api/lessons/{lesson.Id}");
        var body = await get.Content.ReadFromJsonAsync<LessonResponse>();
        body!.Title.Should().Be("New");
        body.Content.Should().Be("New body");
    }

    [Fact] // L12
    public async Task Update_with_no_changes_returns_204_idempotent()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Same", "Same body");

        var noOp = await AnaClient().PutAsJsonAsync($"/api/lessons/{lesson.Id}",
            new UpdateLessonRequest("Same", "Same body"));
        noOp.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // L13
    public async Task Delete_on_draft_returns_204_then_get_404()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "ToDelete", "body");

        var del = await AnaClient().DeleteAsync($"/api/lessons/{lesson.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await AnaClient().GetAsync($"/api/lessons/{lesson.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await get.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("lesson_not_found");
    }

    [Fact] // L14
    public async Task Delete_already_deleted_returns_204_idempotent()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "DoubleDelete", "body");
        await AnaClient().DeleteAsync($"/api/lessons/{lesson.Id}");

        var second = await AnaClient().DeleteAsync($"/api/lessons/{lesson.Id}");
        second.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // L15
    public async Task Delete_lesson_with_progress_returns_409_lesson_has_progress()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Active lesson", "body");

        var activate = await AnaClient().PostAsync($"/api/courses/{_courseId}/activate", null);
        activate.EnsureSuccessStatusCode();

        var pera = PeraClient();
        (await pera.PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_courseId, TestIds.PeraUserId))).EnsureSuccessStatusCode();
        (await pera.PostAsync($"/api/lessons/{lesson.Id}/complete", null))
            .EnsureSuccessStatusCode();

        var del = await AnaClient().DeleteAsync($"/api/lessons/{lesson.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await del.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("lesson_has_progress");
    }

    [Fact] // L16
    public async Task Reorder_moves_lesson_to_new_position()
    {
        var a = await CreateLessonAsync(AnaClient(), _courseId, "A", "a");
        var b = await CreateLessonAsync(AnaClient(), _courseId, "B", "b");
        var c = await CreateLessonAsync(AnaClient(), _courseId, "C", "c");

        var reorder = await AnaClient().PostAsJsonAsync(
            $"/api/lessons/{c.Id}/reorder",
            new ReorderLessonRequest(1));
        reorder.StatusCode.Should().Be(HttpStatusCode.OK);
        var refreshed = await reorder.Content.ReadFromJsonAsync<LessonResponse>();
        refreshed!.Position.Should().Be(1);
        refreshed.Id.Should().Be(c.Id);

        var list = (await (await AnaClient().GetAsync($"/api/courses/{_courseId}/lessons"))
            .Content.ReadFromJsonAsync<List<LessonResponse>>())!;
        list.Should().HaveCount(3);
        list[0].Id.Should().Be(c.Id);
        list[1].Id.Should().Be(a.Id);
        list[2].Id.Should().Be(b.Id);
    }

    [Fact] // L17
    public async Task Reorder_position_out_of_range_returns_400()
    {
        var a = await CreateLessonAsync(AnaClient(), _courseId, "A", "a");
        await CreateLessonAsync(AnaClient(), _courseId, "B", "b");
        await CreateLessonAsync(AnaClient(), _courseId, "C", "c");

        var response = await AnaClient().PostAsJsonAsync(
            $"/api/lessons/{a.Id}/reorder",
            new ReorderLessonRequest(99));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("bad_request");
        body.Message.Should().Be("position_out_of_range");
    }

    [Fact] // L18
    public async Task Reorder_position_zero_returns_400_validation_failed()
    {
        var lesson = await CreateLessonAsync(AnaClient(), _courseId, "Solo", "body");

        var response = await AnaClient().PostAsJsonAsync(
            $"/api/lessons/{lesson.Id}/reorder",
            new ReorderLessonRequest(0));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    private async Task<LessonResponse> CreateLessonAsync(HttpClient client, Guid courseId, string title, string content)
    {
        var response = await client.PostAsJsonAsync($"/api/courses/{courseId}/lessons",
            new CreateLessonRequest(title, content));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<LessonResponse>())!;
    }
}
