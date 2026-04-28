using Izvor.Api.Dtos;
using Izvor.Api.Mapping;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class EnrollmentsController : ControllerBase
{
    private const string EnrollmentSelectColumns =
        "id, course_id, user_id, status, enrolled_at, completed_at, cancelled_at, created_at, updated_at";

    private readonly IDbSessionContext _session;

    public EnrollmentsController(IDbSessionContext session)
    {
        _session = session;
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
        Guid id;
        await using (var insertCommand = _session.CreateCommand(
            "SELECT api.enroll_user(@userId, @courseId)"))
        {
            insertCommand.Parameters.AddWithValue("userId", request.UserId);
            insertCommand.Parameters.AddWithValue("courseId", request.CourseId);
            id = (Guid)(await insertCommand.ExecuteScalarAsync(cancellationToken))!;
        }

        var created = await ReadEnrollmentAsync(id, cancellationToken);
        return Created($"/api/enrollments/{id}", created);
    }

    [HttpPost("enrollments/{id:guid}/cancel")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CancelAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.cancel_enrollment(@id)");
        command.Parameters.AddWithValue("id", id);

        // spec.cancel_enrollment raises enrollment_not_found / enrollment_not_active /
        // role-required; on success returns true. Bool ignored — no idempotent path.
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("enrollments/{id:guid}")]
    [ProducesResponseType(typeof(EnrollmentResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<EnrollmentResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        return Ok(await ReadEnrollmentAsync(id, cancellationToken));
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
        await using var command = _session.CreateCommand(
            $"SELECT {EnrollmentSelectColumns} FROM api.list_enrollments_by_user(@userId, @statusFilter)");
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("statusFilter", (object?)query.Status ?? DBNull.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<EnrollmentResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(EnrollmentRowMapper.Map(reader));
        }
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
        await using var command = _session.CreateCommand(
            $"SELECT {EnrollmentSelectColumns} FROM api.list_enrollments_by_course(@courseId, @statusFilter)");
        command.Parameters.AddWithValue("courseId", courseId);
        command.Parameters.AddWithValue("statusFilter", (object?)query.Status ?? DBNull.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<EnrollmentResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(EnrollmentRowMapper.Map(reader));
        }
        return Ok(results);
    }

    private async Task<EnrollmentResponse> ReadEnrollmentAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {EnrollmentSelectColumns} FROM api.get_enrollment(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            // api.get_enrollment raises enrollment_not_found on miss (plpgsql wrapper),
            // so reaching this branch means RLS/transaction inconsistency.
            throw new InvalidOperationException(
                "api.get_enrollment returned empty without raising enrollment_not_found");
        }
        return EnrollmentRowMapper.Map(reader);
    }
}
