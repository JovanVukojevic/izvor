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
public sealed class LessonProgressController : ControllerBase
{
    private const string LessonProgressSelectColumns =
        "id, enrollment_id, lesson_id, completed_at, created_at, updated_at";

    private const string CompletionStatsSelectColumns =
        "course_id, total_enrollments, active_count, completed_count, cancelled_count, average_progress_pct";

    private readonly IDbSessionContext _session;

    public LessonProgressController(IDbSessionContext session)
    {
        _session = session;
    }

    [HttpPost("lessons/{id:guid}/complete")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> MarkCompleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.mark_lesson_complete(@id)");
        command.Parameters.AddWithValue("id", id);

        // spec.mark_lesson_complete is idempotent: false = already complete,
        // true = newly created. Both succeed paths return 204; client follows
        // up with GET /api/enrollments/{id} to detect auto-flip to completed.
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("enrollments/{id:guid}/progress")]
    [ProducesResponseType(typeof(IEnumerable<LessonProgressResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IEnumerable<LessonProgressResponse>>> GetProgressByEnrollmentAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {LessonProgressSelectColumns} FROM api.get_lesson_progress_by_enrollment(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<LessonProgressResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(LessonProgressRowMapper.Map(reader));
        }
        return Ok(results);
    }

    [HttpGet("courses/{id:guid}/completion-stats")]
    [ProducesResponseType(typeof(CourseCompletionStatsResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseCompletionStatsResponse>> GetCompletionStatsAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {CompletionStatsSelectColumns} FROM api.get_course_completion_stats(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "api.get_course_completion_stats returned no row");
        }
        return Ok(CourseCompletionStatsRowMapper.Map(reader));
    }
}
