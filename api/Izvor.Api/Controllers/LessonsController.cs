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
public sealed class LessonsController : ControllerBase
{
    private const string LessonSelectColumns =
        "id, course_id, title, content, position, created_at, updated_at";

    private readonly IDbSessionContext _session;

    public LessonsController(IDbSessionContext session)
    {
        _session = session;
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
        Guid id;
        await using (var insertCommand = _session.CreateCommand(
            "SELECT api.create_lesson(@courseId, @title, @content)"))
        {
            insertCommand.Parameters.AddWithValue("courseId", courseId);
            insertCommand.Parameters.AddWithValue("title", request.Title);
            insertCommand.Parameters.AddWithValue("content", request.Content);
            id = (Guid)(await insertCommand.ExecuteScalarAsync(cancellationToken))!;
        }

        var created = await ReadLessonAsync(id, cancellationToken);
        return Created($"/api/lessons/{id}", created);
    }

    [HttpGet("courses/{courseId:guid}/lessons")]
    [ProducesResponseType(typeof(IEnumerable<LessonResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IEnumerable<LessonResponse>>> ListByCourseAsync(
        Guid courseId,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {LessonSelectColumns} FROM api.list_lessons_by_course(@courseId)");
        command.Parameters.AddWithValue("courseId", courseId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<LessonResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(LessonRowMapper.Map(reader));
        }
        return Ok(results);
    }

    [HttpGet("lessons/{id:guid}")]
    [ProducesResponseType(typeof(LessonResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LessonResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        return Ok(await ReadLessonAsync(id, cancellationToken));
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
        await using var command = _session.CreateCommand(
            "SELECT api.update_lesson(@id, @title, @content)");
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("title", request.Title);
        command.Parameters.AddWithValue("content", request.Content);

        // spec.update_lesson raises lesson_not_found; past that, false means
        // no-change idempotent. Both succeed paths return 204.
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpDelete("lessons/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.delete_lesson(@id)");
        command.Parameters.AddWithValue("id", id);

        // spec.delete_lesson is silently idempotent on missing (per 7.2 hard-delete
        // pattern); raises lesson_has_progress when committed progress exists.
        await command.ExecuteScalarAsync(cancellationToken);
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
        await using (var command = _session.CreateCommand(
            "SELECT api.reorder_lesson(@id, @position)"))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("position", request.Position);
            await command.ExecuteScalarAsync(cancellationToken);
        }

        var refreshed = await ReadLessonAsync(id, cancellationToken);
        return Ok(refreshed);
    }

    private async Task<LessonResponse> ReadLessonAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {LessonSelectColumns} FROM api.get_lesson(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            // api.get_lesson raises lesson_not_found on miss (plpgsql wrapper),
            // so reaching this branch means RLS/transaction inconsistency.
            throw new InvalidOperationException(
                "api.get_lesson returned empty without raising lesson_not_found");
        }
        return LessonRowMapper.Map(reader);
    }
}
