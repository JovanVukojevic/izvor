using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class LessonsController : ControllerBase
{
    private readonly IDbAccess _db;

    public LessonsController(IDbAccess db)
    {
        _db = db;
    }

    [HttpPost("courses/{courseId:guid}/lessons")]
    [ProducesResponseType(typeof(LessonResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<LessonResponse>> CreateAsync(
        Guid courseId,
        [FromBody] CreateLessonRequest request,
        CancellationToken cancellationToken)
    {
        var id = await _db.CallAsync<Guid>(
            "api.create_lesson",
            new { p_course_id = courseId, p_title = request.Title, p_content = request.Content },
            cancellationToken);

        var created = await _db.CallAsync<LessonResponse>(
            "api.get_lesson",
            new { p_lesson_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                "api.get_lesson returned empty without raising lesson_not_found");

        return Created($"/api/lessons/{id}", created);
    }

    [HttpGet("courses/{courseId:guid}/lessons")]
    [ProducesResponseType(typeof(IEnumerable<LessonResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IEnumerable<LessonResponse>>> ListByCourseAsync(
        Guid courseId,
        CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<LessonResponse>(
            "api.list_lessons_by_course",
            new { p_course_id = courseId },
            cancellationToken);
        return Ok(results);
    }

    [HttpGet("lessons/{id:guid}")]
    [ProducesResponseType(typeof(LessonResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LessonResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var lesson = await _db.CallAsync<LessonResponse>(
            "api.get_lesson",
            new { p_lesson_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                "api.get_lesson returned empty without raising lesson_not_found");
        return Ok(lesson);
    }

    [HttpPut("lessons/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateAsync(
        Guid id,
        [FromBody] UpdateLessonRequest request,
        CancellationToken cancellationToken)
    {
        // spec.update_lesson raises lesson_not_found; past that, false means
        // no-change idempotent. Both succeed paths return 204.
        await _db.ExecuteAsync(
            "api.update_lesson",
            new { p_lesson_id = id, p_title = request.Title, p_content = request.Content },
            cancellationToken);
        return NoContent();
    }

    [HttpDelete("lessons/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        // spec.delete_lesson is silently idempotent on missing (per 7.2 hard-delete
        // pattern); raises lesson_has_completions when any learner has completed it.
        await _db.ExecuteAsync(
            "api.delete_lesson",
            new { p_lesson_id = id },
            cancellationToken);
        return NoContent();
    }

    [HttpPost("lessons/{id:guid}/reorder")]
    [ProducesResponseType(typeof(LessonResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<LessonResponse>> ReorderAsync(
        Guid id,
        [FromBody] ReorderLessonRequest request,
        CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.reorder_lesson",
            new { p_lesson_id = id, p_new_position = request.Position },
            cancellationToken);

        var refreshed = await _db.CallAsync<LessonResponse>(
            "api.get_lesson",
            new { p_lesson_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                "api.get_lesson returned empty without raising lesson_not_found");
        return Ok(refreshed);
    }
}
