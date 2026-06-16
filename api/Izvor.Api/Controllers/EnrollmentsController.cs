using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class EnrollmentsController : ControllerBase
{
    private readonly IDbAccess _db;

    public EnrollmentsController(IDbAccess db)
    {
        _db = db;
    }

    [HttpPost("enrollments")]
    [ProducesResponseType(typeof(EnrollmentResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<EnrollmentResponse>> CreateAsync(
        [FromBody] EnrollUserRequest request,
        CancellationToken cancellationToken)
    {
        var created = await _db.CallAsync<EnrollmentResponse>(
            "api.enroll_user",
            new { p_user_id = request.UserId, p_course_id = request.CourseId },
            cancellationToken)
            ?? throw new InvalidOperationException("api.enroll_user returned no row");

        return Created($"/api/enrollments/{created.Id}", created);
    }

    [HttpPost("enrollments/{id:guid}/cancel")]
    [ProducesResponseType(typeof(EnrollmentResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<EnrollmentResponse>> CancelAsync(Guid id, CancellationToken cancellationToken)
    {
        var cancelled = await _db.CallAsync<EnrollmentResponse>(
            "api.cancel_enrollment",
            new { p_enrollment_id = id },
            cancellationToken);
        return Ok(cancelled);
    }

    [HttpGet("enrollments/{id:guid}")]
    [ProducesResponseType(typeof(EnrollmentResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<EnrollmentResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var enrollment = await _db.CallAsync<EnrollmentResponse>(
            "api.get_enrollment",
            new { p_enrollment_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                "api.get_enrollment returned empty without raising enrollment_not_found");
        return Ok(enrollment);
    }

    [HttpGet("users/{userId:guid}/enrollments")]
    [ProducesResponseType(typeof(IEnumerable<EnrollmentResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IEnumerable<EnrollmentResponse>>> ListByUserAsync(
        Guid userId,
        [FromQuery] ListEnrollmentsQuery query,
        CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<EnrollmentResponse>(
            "api.list_enrollments_by_user",
            new { p_user_id = userId, p_status_filter = query.Status },
            cancellationToken);
        return Ok(results);
    }

    [HttpGet("courses/{courseId:guid}/enrollments")]
    [ProducesResponseType(typeof(IEnumerable<EnrollmentResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IEnumerable<EnrollmentResponse>>> ListByCourseAsync(
        Guid courseId,
        [FromQuery] ListEnrollmentsQuery query,
        CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<EnrollmentResponse>(
            "api.list_enrollments_by_course",
            new { p_course_id = courseId, p_status_filter = query.Status },
            cancellationToken);
        return Ok(results);
    }
}
