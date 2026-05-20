using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class LessonProgressController : ControllerBase
{
    private readonly IDbAccess _db;

    public LessonProgressController(IDbAccess db)
    {
        _db = db;
    }

    [HttpPost("lessons/{id:guid}/complete")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> MarkCompleteAsync(Guid id, CancellationToken cancellationToken)
    {
        // spec.mark_lesson_complete is idempotent: false = already complete,
        // true = newly created. Both succeed paths return 204; client follows
        // up with GET /api/enrollments/{id} to detect auto-flip to completed.
        await _db.ExecuteAsync(
            "api.mark_lesson_complete",
            new { p_lesson_id = id },
            cancellationToken);
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
        var results = await _db.QueryAsync<LessonProgressResponse>(
            "api.get_lesson_progress_by_enrollment",
            new { p_enrollment_id = id },
            cancellationToken);
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
        var stats = await _db.CallAsync<CourseCompletionStatsResponse>(
            "api.get_course_completion_stats",
            new { p_course_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                "api.get_course_completion_stats returned no row");
        return Ok(stats);
    }
}
