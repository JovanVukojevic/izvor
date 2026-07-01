using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Izvor.Api.Dtos;
using Izvor.Api.Tests.Fixtures;
using Izvor.Api.Tests.Helpers;
using Xunit;

namespace Izvor.Api.Tests.Endpoints;

[Collection(PostgresCollection.Name)]
public sealed class EnrollmentsEndpointTests : IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private readonly IzvorWebApplicationFactory _factory;
    private Guid _categoryId;
    private Guid _activeCourseId;
    private Guid _inactiveCourseId;

    public EnrollmentsEndpointTests(PostgresFixture postgres)
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

        _activeCourseId = await CreateActiveCourseAsync("Active Course");
        _inactiveCourseId = await CreateCourseAsync("Inactive Course");
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

    [Fact] // E1
    public async Task Self_enroll_in_published_course_succeeds()
    {
        var response = await PeraClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PeraUserId));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var body = await response.Content.ReadFromJsonAsync<EnrollmentResponse>();
        body!.UserId.Should().Be(TestIds.PeraUserId);
        body.CourseId.Should().Be(_activeCourseId);
        body.Status.Should().Be("active");
        body.FinishedAt.Should().BeNull();
        response.Headers.Location!.ToString().Should().Be($"/api/enrollments/{body.Id}");
    }

    [Fact] // E2
    public async Task Admin_can_enroll_other_user_in_published_course()
    {
        var response = await AdminClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PeraUserId));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }

    [Fact] // E3
    public async Task Author_cannot_enroll_other_user()
    {
        var response = await AnaClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PeraUserId));

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
    }

    [Fact] // E5
    public async Task EnrollAsync_on_inactive_course_returns_409_course_inactive()
    {
        var response = await PeraClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_inactiveCourseId, TestIds.PeraUserId));

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("course_inactive");
    }

    [Fact] // E6
    public async Task Self_enroll_when_already_active_returns_409()
    {
        var first = await PeraClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PeraUserId));
        first.EnsureSuccessStatusCode();

        var second = await PeraClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PeraUserId));

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await second.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("already_exists");
        body.Message.Should().Be("enrollment_already_active");
    }

    [Fact] // E7
    public async Task Admin_enroll_inactive_user_returns_403_account_inactive()
    {
        var response = await AdminClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.InactiveUserId));

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("account_inactive");
        body.Message.Should().Be("user_inactive");
    }

    [Fact] // E8
    public async Task Admin_enroll_user_from_other_tenant_returns_404()
    {
        // Acme admin targets an Intellya user — RLS hides them, so user_not_found.
        var response = await AdminClient().PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(_activeCourseId, TestIds.PetarUserId));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("not_found");
        body.Message.Should().Be("user_not_found");
    }

    [Fact] // E9
    public async Task Cancel_own_active_enrollment_succeeds()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var cancel = await PeraClient().PostAsync($"/api/enrollments/{enrollment.Id}/cancel", null);
        cancel.StatusCode.Should().Be(HttpStatusCode.OK);

        var body = await cancel.Content.ReadFromJsonAsync<EnrollmentResponse>();
        body!.Status.Should().Be("cancelled");
        body.FinishedAt.Should().NotBeNull();
    }

    [Fact] // E10
    public async Task Admin_can_cancel_others_enrollment()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var cancel = await AdminClient().PostAsync($"/api/enrollments/{enrollment.Id}/cancel", null);
        cancel.StatusCode.Should().Be(HttpStatusCode.OK);

        var body = await cancel.Content.ReadFromJsonAsync<EnrollmentResponse>();
        body!.Status.Should().Be("cancelled");
    }

    [Fact] // E11
    public async Task Author_cannot_cancel_enrollment()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var cancel = await AnaClient().PostAsync($"/api/enrollments/{enrollment.Id}/cancel", null);
        cancel.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await cancel.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
    }

    [Fact] // E12
    public async Task Cancel_already_cancelled_returns_409()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);
        await PeraClient().PostAsync($"/api/enrollments/{enrollment.Id}/cancel", null);

        var second = await PeraClient().PostAsync($"/api/enrollments/{enrollment.Id}/cancel", null);
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        var body = await second.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("state_invalid");
        body.Message.Should().Be("enrollment_not_active");
    }

    [Fact] // E13
    public async Task Get_enrollment_returns_data()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var response = await PeraClient().GetAsync($"/api/enrollments/{enrollment.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<EnrollmentResponse>();
        body!.Id.Should().Be(enrollment.Id);
        body.Status.Should().Be("active");
    }

    [Fact] // E14
    public async Task Cross_tenant_get_enrollment_returns_404()
    {
        var enrollment = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var response = await PetarClient().GetAsync($"/api/enrollments/{enrollment.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Message.Should().Be("enrollment_not_found");
    }

    [Fact] // E15
    public async Task List_enrollments_by_user_self_succeeds()
    {
        await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var response = await PeraClient().GetAsync($"/api/users/{TestIds.PeraUserId}/enrollments");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = (await response.Content.ReadFromJsonAsync<List<EnrollmentResponse>>())!;
        list.Should().HaveCount(1);
        list[0].UserId.Should().Be(TestIds.PeraUserId);
    }

    [Fact] // E16
    public async Task List_enrollments_by_user_for_other_returns_403_for_learner()
    {
        await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var response = await IvanaClient().GetAsync($"/api/users/{TestIds.PeraUserId}/enrollments");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Be("not_authorized");
    }

    [Fact] // E17
    public async Task List_enrollments_by_course_owner_succeeds()
    {
        await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var response = await AnaClient().GetAsync($"/api/courses/{_activeCourseId}/enrollments");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await response.Content.ReadFromJsonAsync<List<EnrollmentResponse>>();
        list!.Should().HaveCount(1);
    }

    [Fact] // E18
    public async Task List_enrollments_by_course_non_owner_learner_returns_403()
    {
        var response = await PeraClient().GetAsync($"/api/courses/{_activeCourseId}/enrollments");
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("forbidden");
        body.Message.Should().Be("not_course_owner");
    }

    [Fact] // E19
    public async Task List_enrollments_with_status_filter()
    {
        var first = await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);
        await PeraClient().PostAsync($"/api/enrollments/{first.Id}/cancel", null);
        await EnrollAsync(PeraClient(), _activeCourseId, TestIds.PeraUserId);

        var active = await PeraClient().GetAsync($"/api/users/{TestIds.PeraUserId}/enrollments?status=active");
        var activeList = (await active.Content.ReadFromJsonAsync<List<EnrollmentResponse>>())!;
        activeList.Should().HaveCount(1);
        activeList[0].Status.Should().Be("active");

        var cancelled = await PeraClient().GetAsync($"/api/users/{TestIds.PeraUserId}/enrollments?status=cancelled");
        var cancelledList = (await cancelled.Content.ReadFromJsonAsync<List<EnrollmentResponse>>())!;
        cancelledList.Should().HaveCount(1);
        cancelledList[0].Status.Should().Be("cancelled");
    }

    [Fact] // E20
    public async Task List_enrollments_with_invalid_status_returns_400()
    {
        var response = await PeraClient().GetAsync($"/api/users/{TestIds.PeraUserId}/enrollments?status=banana");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        body!.Error.Should().Be("validation_failed");
    }

    private async Task<EnrollmentResponse> EnrollAsync(HttpClient client, Guid courseId, Guid userId)
    {
        var response = await client.PostAsJsonAsync("/api/enrollments",
            new EnrollUserRequest(courseId, userId));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<EnrollmentResponse>())!;
    }

    private async Task<Guid> CreateActiveCourseAsync(string title)
    {
        // CreateCourseAsync already inserts the first lesson (migration 027),
        // so activation precondition (≥1 lesson) is satisfied by construction.
        var id = await CreateCourseAsync(title);
        var activate = await AnaClient().PostAsync($"/api/courses/{id}/activate", null);
        activate.EnsureSuccessStatusCode();
        return id;
    }

    private async Task<Guid> CreateCourseAsync(string title)
    {
        var resp = await AnaClient().PostAsJsonAsync("/api/courses",
            new CreateCourseRequest(title, null, new[] { _categoryId },
                new[] { new CreateLessonInput("First lesson", "seed") }));
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<CourseResponse>())!.Id;
    }
}
