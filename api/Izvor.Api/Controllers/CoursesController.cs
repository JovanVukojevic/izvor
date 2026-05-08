using Izvor.Api.Dtos;
using Izvor.Api.Mapping;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/courses")]
[Authorize]
public sealed class CoursesController : ControllerBase
{
    private const string CourseSelectColumns =
        "id, category_id, author_id, title, description, created_at, updated_at, is_active";

    private readonly IDbSessionContext _session;

    public CoursesController(IDbSessionContext session)
    {
        _session = session;
    }

    [HttpPost]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CourseResponse>> CreateAsync(
        [FromBody] CreateCourseRequest request,
        CancellationToken cancellationToken)
    {
        Guid id;
        await using (var insertCommand = _session.CreateCommand(
            "SELECT api.create_course(@title, @description, @categoryId)"))
        {
            insertCommand.Parameters.AddWithValue("title", request.Title);
            insertCommand.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
            insertCommand.Parameters.AddWithValue("categoryId", (object?)request.CategoryId ?? DBNull.Value);
            id = (Guid)(await insertCommand.ExecuteScalarAsync(cancellationToken))!;
        }

        var created = await ReadCourseAsync(id, cancellationToken);
        return Created($"/api/courses/{id}", created);
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateAsync(
        Guid id,
        [FromBody] UpdateCourseRequest request,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            "SELECT api.update_course(@id, @title, @description, @categoryId)");
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("title", request.Title);
        command.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
        command.Parameters.AddWithValue("categoryId", (object?)request.CategoryId ?? DBNull.Value);

        // spec.update_course gates with assert_course_owner_or_admin which raises
        // course_not_found / not_course_owner. Past the assert, false means the
        // no-change short-circuit (idempotent no-op). Both paths return 204.
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.delete_course(@id)");
        command.Parameters.AddWithValue("id", id);

        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {CourseSelectColumns} FROM api.get_course(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return NotFound(new ErrorResponse("not_found", "course_not_found"));
        }
        return Ok(CourseRowMapper.Map(reader));
    }

    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<CourseResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IEnumerable<CourseResponse>>> ListAsync(
        [FromQuery] ListCoursesQuery query,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {CourseSelectColumns} FROM api.list_courses(@categoryFilter, @activeFilter)");
        command.Parameters.AddWithValue("categoryFilter", (object?)query.CategoryId ?? DBNull.Value);
        command.Parameters.AddWithValue("activeFilter", (object?)query.Active ?? DBNull.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<CourseResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(CourseRowMapper.Map(reader));
        }
        return Ok(results);
    }

    [HttpPost("{id:guid}/activate")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CourseResponse>> ActivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await using (var activate = _session.CreateCommand("SELECT api.activate_course(@id)"))
        {
            activate.Parameters.AddWithValue("id", id);
            await activate.ExecuteScalarAsync(cancellationToken);
        }

        var refreshed = await ReadCourseAsync(id, cancellationToken);
        return Ok(refreshed);
    }

    [HttpPost("{id:guid}/deactivate")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseResponse>> DeactivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await using (var deactivate = _session.CreateCommand("SELECT api.deactivate_course(@id)"))
        {
            deactivate.Parameters.AddWithValue("id", id);
            await deactivate.ExecuteScalarAsync(cancellationToken);
        }

        var refreshed = await ReadCourseAsync(id, cancellationToken);
        return Ok(refreshed);
    }

    private async Task<CourseResponse> ReadCourseAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {CourseSelectColumns} FROM api.get_course(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                $"Course {id} disappeared after creation — RLS or transaction issue");
        }
        return CourseRowMapper.Map(reader);
    }
}
