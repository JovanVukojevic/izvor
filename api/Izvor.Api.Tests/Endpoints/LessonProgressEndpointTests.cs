using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class LessonProgressEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private Guid _categoryId;

    private Guid _p1CourseId;
    private Guid _p1L1;
    private Guid _p1L2;
    private Guid _p1L3;
    private Guid _peraP1EnrollmentId;

    public LessonProgressEndpointTests(PostgresFixture postgres)
    {
        _postgres = postgres;
        _factory = new IzvorWebApplicationFactory(_postgres.AppConnectionString);
    }

    public async Task InitializeAsync()
    {
        await TestSeed.ResetCategoriesAndCoursesAsync(_postgres.AdminConnectionString);

        var catResp = await AdminClient().PostAsJsonAsync("/api/categories",
            new CreateCategoryRequest("Default", null));
        catResp.EnsureSuccessStatusCode();
        _categoryId = (await catResp.Content.ReadFromJsonAsync<CategoryResponse>())!.Id;

        // Course is created with its first lesson inline (migration 027); _p1L1
        // tracks that auto-created lesson, and _p1L2 / _p1L3 are added after.
        // Total lessons on the course = 3, matching this suite's prior expectations
        // (LP7 auto-flip after 3 marks; LP13 avg-progress denominator of 3).
        _p1CourseId = await CreateCourseAsync("P1");
        _p1L1 = (await ListLessonsAsync(_p1CourseId))[0].Id;
        _p1L2 = (await CreateLessonAsync(_p1CourseId, "L2", "b")).Id;
        _p1L3 = (await CreateLessonAsync(_p1CourseId, "L3", "c")).Id;
        await ActivateCourseAsync(_p1CourseId);

        var enr = await EnrollAsync(PeraClient(), _p1CourseId, TestIds.PeraUserId);
        _peraP1EnrollmentId = enr.Id;
    }

    public Task DisposeAsync()
    {
        _factory.Dispose();
        return Task.CompletedTask;
    }

    private HttpClient AdminClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.MarkoUserId, "admin", TestIds.MarkoEmail, TestIds.AcmeTenantId);
    private HttpClient AnaClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.AnaUserId, "author", TestIds.AnaEmail, TestIds.AcmeTenantId);
    private HttpClient PeraClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.PeraUserId, "learner", TestIds.PeraEmail, TestIds.AcmeTenantId);
    private HttpClient IvanaClient() => MakeClient(TestIds.AcmeSubdomain, TestIds.IvanaUserId, "learner", TestIds.IvanaEmail, TestIds.AcmeTenantId);
    private HttpClient PetarClient() => MakeClient(TestIds.IntellyaSubdomain, TestIds.PetarUserId, "author", TestIds.PetarEmail, TestIds.IntellyaTenantId);

    private HttpClient MakeClient(string subdomain, Guid userId, string role, string email, Guid tenantId) =>
        _factory.CreateClient()
            .WithTenant(subdomain)
            .WithBearer(AuthHelper.MintToken(_factory.Services, userId, tenantId, role, email));

    [Fact] // LP1
    public async Task Mark_lesson_complete_first_time_returns_204()
    {
        var response = await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // LP2
    public async Task Mark_lesson_complete_idempotent_second_call_returns_204()
    {
        await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        var response = await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact] // LP3
    public async Task Mark_lesson_complete_when_not_enrolled_returns_409()
    {
        // Marko is admin but never enrolled. Self-only auth means no special privilege.
        // not_enrolled is mapped to state_invalid (409) — the relationship state, not auth.
        var response = await AdminClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("not_enrolled");
    }

    [Fact] // LP4
    public async Task Mark_lesson_complete_with_cancelled_enrollment_returns_409()
    {
        await PeraClient().PostAsync($"/api/enrollments/{_peraP1EnrollmentId}/cancel", null);

        var response = await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("enrollment_cancelled");
    }

    [Fact] // LP7
    public async Task Auto_flip_to_completed_when_all_lessons_done()
    {
        (await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null)).EnsureSuccessStatusCode();
        (await PeraClient().PostAsync($"/api/lessons/{_p1L2}/complete", null)).EnsureSuccessStatusCode();
        (await PeraClient().PostAsync($"/api/lessons/{_p1L3}/complete", null)).EnsureSuccessStatusCode();

        var get = await PeraClient().GetAsync($"/api/enrollments/{_peraP1EnrollmentId}");
        get.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await get.Content.ReadFromJsonAsync<EnrollmentResponse>();
        body!.Status.Should().Be("completed");
        body.CompletedAt.Should().NotBeNull();
    }

    [Fact] // LP8
    public async Task Cross_tenant_mark_complete_returns_404()
    {
        // Petar is in Intellya; lesson belongs to Acme. RLS hides → lesson_not_found.
        var response = await PetarClient().PostAsync($"/api/lessons/{_p1L1}/complete", null);
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("lesson_not_found");
    }

    [Fact] // LP9
    public async Task Get_progress_by_enrollment_for_self_succeeds()
    {
        (await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null)).EnsureSuccessStatusCode();

        var response = await PeraClient().GetAsync($"/api/enrollments/{_peraP1EnrollmentId}/completions");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = (await response.Content.ReadFromJsonAsync<List<LessonCompletionResponse>>())!;
        list.Should().HaveCount(1);
        list[0].LessonId.Should().Be(_p1L1);
        list[0].EnrollmentId.Should().Be(_peraP1EnrollmentId);
    }

    [Fact] // LP10
    public async Task Get_progress_by_enrollment_for_course_author_succeeds()
    {
        (await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null)).EnsureSuccessStatusCode();

        var response = await AnaClient().GetAsync($"/api/enrollments/{_peraP1EnrollmentId}/completions");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<LessonCompletionResponse>>();
        list!.Should().HaveCount(1);
    }

    [Fact] // LP11
    public async Task Get_progress_by_enrollment_for_admin_succeeds()
    {
        (await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null)).EnsureSuccessStatusCode();

        var response = await AdminClient().GetAsync($"/api/enrollments/{_peraP1EnrollmentId}/completions");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact] // LP12
    public async Task Get_progress_by_enrollment_for_unrelated_learner_returns_403()
    {
        // Ivana is a learner in Acme who is neither the enrollment owner nor course author.
        var response = await IvanaClient().GetAsync($"/api/enrollments/{_peraP1EnrollmentId}/completions");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Be("not_authorized");
    }

    [Fact] // LP13
    public async Task Get_completion_stats_for_course_owner_returns_aggregation()
    {
        (await PeraClient().PostAsync($"/api/lessons/{_p1L1}/complete", null)).EnsureSuccessStatusCode();

        var response = await AnaClient().GetAsync($"/api/courses/{_p1CourseId}/completion-stats");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<CourseCompletionStatsResponse>();
        body!.CourseId.Should().Be(_p1CourseId);
        body.TotalEnrollments.Should().Be(1);
        body.ActiveCount.Should().Be(1);
        body.CompletedCount.Should().Be(0);
        body.CancelledCount.Should().Be(0);
        body.AverageProgressPct.Should().Be(33.33m);
    }

    [Fact] // LP14
    public async Task Get_completion_stats_for_non_owner_learner_returns_403()
    {
        var response = await PeraClient().GetAsync($"/api/courses/{_p1CourseId}/completion-stats");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Be("not_course_owner");
    }

    [Fact] // LP15
    public async Task Get_completion_stats_for_course_with_no_enrollments_returns_zeros()
    {
        var courseId = await CreateCourseAsync("NoEnrollments");

        var response = await AnaClient().GetAsync($"/api/courses/{courseId}/completion-stats");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<CourseCompletionStatsResponse>();
        body!.TotalEnrollments.Should().Be(0);
        body.ActiveCount.Should().Be(0);
        body.CompletedCount.Should().Be(0);
        body.CancelledCount.Should().Be(0);
        body.AverageProgressPct.Should().Be(0.00m);
    }

    [Fact] // LP16
    public async Task Cross_tenant_completion_stats_returns_404()
    {
        // Petar is Intellya author; assert_course_owner_or_admin looks up the
        // Acme course via RLS-scoped Intellya session and finds nothing → course_not_found.
        var response = await PetarClient().GetAsync($"/api/courses/{_p1CourseId}/completion-stats");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("course_not_found");
    }

    private async Task<EnrollmentResponse> EnrollAsync(HttpClient client, Guid courseId, Guid userId)
    {
        var response = await client.PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(courseId, userId));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<EnrollmentResponse>())!;
    }

    private async Task<Guid> CreateCourseAsync(string title)
    {
        var resp = await AnaClient().PostAsJsonAsync("/api/courses",
            new CreateCourseRequest(title, null, new[] { _categoryId }, "Fixture intro", "seed"));
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<CourseResponse>())!.Id;
    }

    private async Task ActivateCourseAsync(Guid courseId)
    {
        var resp = await AnaClient().PostAsync($"/api/courses/{courseId}/activate", null);
        resp.EnsureSuccessStatusCode();
    }

    private async Task<List<LessonResponse>> ListLessonsAsync(Guid courseId)
    {
        var resp = await AnaClient().GetAsync($"/api/courses/{courseId}/lessons");
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<List<LessonResponse>>())!;
    }

    private async Task<LessonResponse> CreateLessonAsync(Guid courseId, string title, string content)
    {
        var resp = await AnaClient().PostAsJsonAsync($"/api/courses/{courseId}/lessons",
            new CreateLessonRequest(title, content));
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<LessonResponse>())!;
    }
}
