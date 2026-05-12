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
public sealed class CoursesEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private Guid _categoryId;

    public CoursesEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync()
    {
        await TestSeed.ResetCategoriesAndCoursesAsync(_postgres.AdminConnectionString);

        // Seed one category for course tests, owned by Acme.
        var admin = AdminClient();
        var response = await admin.PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("Default", null));
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<CategoryResponse>();
        _categoryId = body!.Id;
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

    [Fact] // K1
    public async Task Author_can_create_course()
    {
        var ana = AnaClient();
        var response = await ana.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Intro to FP", "Functional programming basics", _categoryId));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var body = await response.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Title.Should().Be("Intro to FP");
        body.AuthorId.Should().Be(TestIds.AnaUserId);
    }

    [Fact] // K2
    public async Task Admin_can_create_course()
    {
        var admin = AdminClient();
        var response = await admin.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Admin course", null, _categoryId));
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }

    [Fact] // K3
    public async Task Learner_create_course_is_forbidden()
    {
        var pera = PeraClient();
        var response = await pera.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Should fail", null, _categoryId));
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
    }

    [Fact] // K4
    public async Task Create_with_invalid_category_id_returns_404_category_not_found()
    {
        // spec.create_course catches FK violation and re-raises 'category_not_found',
        // which the global mapper classifies as 404 not_found (consistent with all
        // other *_not_found codes). REST-purity argument for 409 here is weaker than
        // mapper-consistency.
        var ana = AnaClient();
        var response = await ana.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Bad cat", null, Guid.NewGuid()));
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
        body.Message.Should().Be("category_not_found");
    }

    [Fact] // K4b
    public async Task Create_with_null_category_returns_400_validation_failed()
    {
        var ana = AnaClient();
        var response = await ana.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest("Missing cat", null, null));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    [Fact] // K4c
    public async Task Update_with_null_category_returns_400_validation_failed()
    {
        var draft = await CreateCourseAsync(AnaClient(), "NeedsCat");
        var response = await AnaClient().PutAsJsonAsync($"/api/courses/{draft.Id}",
            new UpdateCourseRequest("NewTitle", null, null));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    [Fact] // K6b
    public async Task List_with_no_filter_returns_active_and_inactive()
    {
        var ana = AnaClient();

        await CreateCourseAsync(ana, "Inactive course");
        var activeId = await CreateActiveCourseAsync(ana, "Active course");

        var response = await ana.GetAsync("/api/courses");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<CourseResponse>>();
        list!.Should().HaveCount(2);
        list!.Should().Contain(c => c.Id == activeId && c.IsActive);
    }

    [Fact] // K7
    public async Task Get_by_id_returns_course()
    {
        var draft = await CreateCourseAsync(AnaClient(), "GetMe");
        var response = await AnaClient().GetAsync($"/api/courses/{draft.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Id.Should().Be(draft.Id);
    }

    [Fact] // K8
    public async Task Owner_can_update_title()
    {
        var draft = await CreateCourseAsync(AnaClient(), "OldTitle");
        var update = await AnaClient().PutAsJsonAsync($"/api/courses/{draft.Id}",
            new UpdateCourseRequest("NewTitle", null, _categoryId));
        update.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await AnaClient().GetAsync($"/api/courses/{draft.Id}");
        var body = await get.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Title.Should().Be("NewTitle");
    }

    [Fact] // K9
    public async Task Cross_tenant_update_returns_404()
    {
        var draft = await CreateCourseAsync(AnaClient(), "AcmeCourse");

        var petar = PetarClient();
        var response = await petar.PutAsJsonAsync($"/api/courses/{draft.Id}",
            new UpdateCourseRequest("Hijack", null, _categoryId));
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("course_not_found");
    }

    [Fact] // K10
    public async Task Same_tenant_non_owner_non_admin_update_is_forbidden()
    {
        var draft = await CreateCourseAsync(AnaClient(), "AnaCourse");
        var pera = PeraClient();
        var response = await pera.PutAsJsonAsync($"/api/courses/{draft.Id}",
            new UpdateCourseRequest("Stolen", null, _categoryId));
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("not_course_owner");
    }

    [Fact] // K13
    public async Task Update_with_no_changes_returns_204_idempotent()
    {
        var draft = await CreateCourseAsync(AnaClient(), "NoChange");

        var noOp = await AnaClient().PutAsJsonAsync($"/api/courses/{draft.Id}",
            new UpdateCourseRequest("NoChange", null, _categoryId));
        noOp.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // K14b
    public async Task DeleteAsync_without_enrollments_then_get_returns_404()
    {
        var ana = AnaClient();
        var draft = await CreateCourseAsync(ana, "HardDeleteTarget");
        var lesson = await ana.PostAsJsonAsync(
            $"/api/courses/{draft.Id}/lessons",
            new CreateLessonRequest("L1", "body"));
        lesson.EnsureSuccessStatusCode();

        var del = await ana.DeleteAsync($"/api/courses/{draft.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var get = await ana.GetAsync($"/api/courses/{draft.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact] // K15b
    public async Task DeleteAsync_with_enrollments_returns_409_course_has_enrollments()
    {
        var ana = AnaClient();
        var courseId = await CreateActiveCourseAsync(ana, "DeleteWithEnrollments");

        var pera = PeraClient();
        (await pera.PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(courseId, TestIds.PeraUserId))).EnsureSuccessStatusCode();

        var del = await ana.DeleteAsync($"/api/courses/{courseId}");
        del.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await del.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("course_has_enrollments");
    }

    [Fact] // K21
    public async Task Get_returns_is_active_false_for_fresh_course()
    {
        var draft = await CreateCourseAsync(AnaClient(), "Fresh");
        var get = await AnaClient().GetAsync($"/api/courses/{draft.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await get.Content.ReadFromJsonAsync<CourseResponse>();
        body!.IsActive.Should().BeFalse();
    }

    [Fact] // K22
    public async Task List_with_active_filter_true_excludes_inactive_courses()
    {
        var ana = AnaClient();
        var inactive = await CreateCourseAsync(ana, "Inactive");
        var active = await CreateActiveCourseAsync(ana, "Active");

        var response = await ana.GetAsync("/api/courses?active=true");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<CourseResponse>>();
        list!.Should().Contain(c => c.Id == active);
        list!.Should().NotContain(c => c.Id == inactive.Id);
    }

    [Fact] // K23
    public async Task List_with_active_filter_false_returns_only_inactive_courses()
    {
        var ana = AnaClient();
        var inactive = await CreateCourseAsync(ana, "Inactive");
        await CreateActiveCourseAsync(ana, "Active");

        var response = await ana.GetAsync("/api/courses?active=false");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<CourseResponse>>();
        list!.Should().HaveCount(1);
        list![0].Id.Should().Be(inactive.Id);
        list![0].IsActive.Should().BeFalse();
    }

    [Fact] // K26
    public async Task ActivateAsync_unknown_id_returns_404_course_not_found()
    {
        var response = await AnaClient().PostAsync($"/api/courses/{Guid.NewGuid()}/activate", null);
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("course_not_found");
    }

    [Fact] // K27
    public async Task ActivateAsync_as_learner_returns_403()
    {
        // Ana (author) creates the course; Pera (learner) attempts to
        // activate. Either layer of defense may fire first
        // (RLS-hidden / not_course_owner / role check) — accept any 403.
        var draft = await CreateCourseAsync(AnaClient(), "ProtectedActivate");

        var response = await PeraClient().PostAsync($"/api/courses/{draft.Id}/activate", null);
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact] // K16
    public async Task Cross_tenant_jwt_mismatch_is_forbidden()
    {
        var client = _factory.CreateClient()
            .WithTenant(TestIds.IntellyaSubdomain)
            .WithBearer(AuthHelper.MintToken(
                _factory.Services, TestIds.AnaUserId, TestIds.AcmeTenantId, "author", TestIds.AnaEmail));

        var response = await client.GetAsync("/api/courses");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("tenant_mismatch");
    }

    [Fact] // K18
    public async Task Activate_course_with_lessons_succeeds()
    {
        var draft = await CreateCourseAsync(AnaClient(), "Activatable");
        var lesson = await AnaClient().PostAsJsonAsync(
            $"/api/courses/{draft.Id}/lessons",
            new CreateLessonRequest("Lesson 1", "body"));
        lesson.EnsureSuccessStatusCode();

        var activate = await AnaClient().PostAsync($"/api/courses/{draft.Id}/activate", null);
        activate.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await activate.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Id.Should().Be(draft.Id);
        body.IsActive.Should().BeTrue();
    }

    [Fact] // K19
    public async Task Activate_empty_course_returns_409_course_has_no_lessons()
    {
        var draft = await CreateCourseAsync(AnaClient(), "Empty");

        var activate = await AnaClient().PostAsync($"/api/courses/{draft.Id}/activate", null);
        activate.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await activate.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("course_has_no_lessons");
    }

    [Fact] // K20
    public async Task Activate_already_active_returns_200_idempotent()
    {
        var ana = AnaClient();
        var courseId = await CreateActiveCourseAsync(ana, "AlreadyActive");

        var second = await ana.PostAsync($"/api/courses/{courseId}/activate", null);
        second.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await second.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Id.Should().Be(courseId);
        body.IsActive.Should().BeTrue();
    }

    [Fact] // K28
    public async Task DeactivateAsync_active_course_returns_200_and_is_active_false()
    {
        var ana = AnaClient();
        var courseId = await CreateActiveCourseAsync(ana, "ToDeactivate");

        var deactivate = await ana.PostAsync($"/api/courses/{courseId}/deactivate", null);
        deactivate.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await deactivate.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Id.Should().Be(courseId);
        body.IsActive.Should().BeFalse();
    }

    [Fact] // K29
    public async Task DeactivateAsync_already_inactive_returns_200_and_is_active_false()
    {
        var ana = AnaClient();
        var draft = await CreateCourseAsync(ana, "FreshInactive");

        var deactivate = await ana.PostAsync($"/api/courses/{draft.Id}/deactivate", null);
        deactivate.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await deactivate.Content.ReadFromJsonAsync<CourseResponse>();
        body!.Id.Should().Be(draft.Id);
        body.IsActive.Should().BeFalse();
    }

    [Fact] // K30
    public async Task DeactivateAsync_unknown_id_returns_404()
    {
        var response = await AnaClient().PostAsync($"/api/courses/{Guid.NewGuid()}/deactivate", null);
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("course_not_found");
    }

    [Fact] // K31
    public async Task DeactivateAsync_as_learner_returns_403()
    {
        // Ana (author) creates the active course; Pera (learner) attempts to
        // deactivate. Either layer of defense may fire first
        // (RLS-hidden / not_course_owner / role check) — accept any 403.
        var courseId = await CreateActiveCourseAsync(AnaClient(), "ProtectedDeactivate");

        var response = await PeraClient().PostAsync($"/api/courses/{courseId}/deactivate", null);
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    private async Task<CourseResponse> CreateCourseAsync(HttpClient client, string title)
    {
        var response = await client.PostAsJsonAsync("/api/courses",
            new CreateCourseRequest(title, null, _categoryId));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<CourseResponse>())!;
    }

    private async Task<Guid> CreateActiveCourseAsync(HttpClient client, string title)
    {
        var draft = await CreateCourseAsync(client, title);
        (await client.PostAsJsonAsync(
            $"/api/courses/{draft.Id}/lessons",
            new CreateLessonRequest("L1", "body"))).EnsureSuccessStatusCode();
        (await client.PostAsync($"/api/courses/{draft.Id}/activate", null))
            .EnsureSuccessStatusCode();
        return draft.Id;
    }
}
