using System.Text.Json;
using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/courses")]
[Authorize]
public sealed class CoursesController : ControllerBase
{
    // Serializes lesson objects with lowercase keys (title/content) so they match the
    // procedure's elem->>'title' / elem->>'content' reads. A casing mismatch would make
    // those reads return NULL and trip the lessons NOT NULL/CHECK constraints.
    private static readonly JsonSerializerOptions LessonsJsonOptions =
        new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private readonly IDbAccess _db;

    public CoursesController(IDbAccess db)
    {
        _db = db;
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
        var lessonsJson = JsonSerializer.Serialize(request.Lessons, LessonsJsonOptions);
        var created = await _db.CallAsync<CourseResponse>(
            "api.create_course",
            new
            {
                p_title = request.Title,
                p_description = request.Description,
                p_category_ids = request.CategoryIds,
                p_lessons = new JsonbParameter(lessonsJson)
            },
            cancellationToken)
            ?? throw new InvalidOperationException("api.create_course returned no row");

        return Created($"/api/courses/{created.Id}", created);
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CourseResponse>> UpdateAsync(
        Guid id,
        [FromBody] UpdateCourseRequest request,
        CancellationToken cancellationToken)
    {
        var updated = await _db.CallAsync<CourseResponse>(
            "api.update_course",
            new { p_id = id, p_title = request.Title, p_description = request.Description, p_category_ids = request.CategoryIds },
            cancellationToken);
        return Ok(updated);
    }

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.delete_course",
            new { p_id = id },
            cancellationToken);
        return NoContent();
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var course = await _db.CallAsync<CourseResponse>(
            "api.get_course",
            new { p_id = id },
            cancellationToken);

        if (course is null)
        {
            return NotFound(new ErrorResponse("not_found", "course_not_found"));
        }
        return Ok(course);
    }

    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<CourseResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IEnumerable<CourseResponse>>> ListAsync(
        [FromQuery] ListCoursesQuery query,
        CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<CourseResponse>(
            "api.list_courses",
            new { p_category_filter = query.CategoryId, p_active_filter = query.Active },
            cancellationToken);
        return Ok(results);
    }

    [HttpPost("{id:guid}/activate")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CourseResponse>> ActivateAsync(Guid id, CancellationToken cancellationToken)
    {
        var activated = await _db.CallAsync<CourseResponse>(
            "api.activate_course",
            new { p_course_id = id },
            cancellationToken);
        return Ok(activated);
    }

    [HttpPost("{id:guid}/deactivate")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseResponse>> DeactivateAsync(Guid id, CancellationToken cancellationToken)
    {
        var deactivated = await _db.CallAsync<CourseResponse>(
            "api.deactivate_course",
            new { p_course_id = id },
            cancellationToken);
        return Ok(deactivated);
    }
}
