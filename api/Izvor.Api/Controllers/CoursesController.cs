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
        var id = await _db.CallAsync<Guid>(
            "api.create_course",
            new { p_title = request.Title, p_description = request.Description, p_category_id = request.CategoryId },
            cancellationToken);

        var created = await _db.CallAsync<CourseResponse>(
            "api.get_course",
            new { p_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                $"Course {id} disappeared after creation — RLS or transaction issue");

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
        // spec.update_course gates with assert_course_owner_or_admin which raises
        // course_not_found / not_course_owner. Past the assert, false means the
        // no-change short-circuit (idempotent no-op). Both paths return 204.
        await _db.ExecuteAsync(
            "api.update_course",
            new { p_id = id, p_title = request.Title, p_description = request.Description, p_category_id = request.CategoryId },
            cancellationToken);
        return NoContent();
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
        await _db.ExecuteAsync(
            "api.activate_course",
            new { p_course_id = id },
            cancellationToken);

        var refreshed = await _db.CallAsync<CourseResponse>(
            "api.get_course",
            new { p_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                $"Course {id} disappeared after activate — RLS or transaction issue");
        return Ok(refreshed);
    }

    [HttpPost("{id:guid}/deactivate")]
    [ProducesResponseType(typeof(CourseResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CourseResponse>> DeactivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.deactivate_course",
            new { p_course_id = id },
            cancellationToken);

        var refreshed = await _db.CallAsync<CourseResponse>(
            "api.get_course",
            new { p_id = id },
            cancellationToken)
            ?? throw new InvalidOperationException(
                $"Course {id} disappeared after deactivate — RLS or transaction issue");
        return Ok(refreshed);
    }
}
