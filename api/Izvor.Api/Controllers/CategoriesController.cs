using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/categories")]
[Authorize]
public sealed class CategoriesController : ControllerBase
{
    private readonly IDbAccess _db;

    public CategoriesController(IDbAccess db)
    {
        _db = db;
    }

    [HttpPost]
    [ProducesResponseType(typeof(CategoryResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CategoryResponse>> CreateAsync(
        [FromBody] CreateCategoryRequest request,
        CancellationToken cancellationToken)
    {
        var created = await _db.CallAsync<CategoryResponse>(
            "api.create_category",
            new { p_name = request.Name, p_description = request.Description },
            cancellationToken)
            ?? throw new InvalidOperationException("api.create_category returned no row");

        return Created($"/api/categories/{created.Id}", created);
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateAsync(
        Guid id,
        [FromBody] UpdateCategoryRequest request,
        CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.update_category",
            new { p_id = id, p_name = request.Name, p_description = request.Description },
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
        var result = await _db.CallAsync<bool>(
            "api.delete_category",
            new { p_id = id },
            cancellationToken);

        if (!result)
        {
            return NotFound(new ErrorResponse("not_found", "category_not_found"));
        }
        return NoContent();
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(CategoryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CategoryResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var category = await _db.CallAsync<CategoryResponse>(
            "api.get_category",
            new { p_id = id },
            cancellationToken);

        if (category is null)
        {
            return NotFound(new ErrorResponse("not_found", "category_not_found"));
        }
        return Ok(category);
    }

    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<CategoryResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IEnumerable<CategoryResponse>>> ListAsync(CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<CategoryResponse>(
            "api.list_categories",
            cancellationToken: cancellationToken);
        return Ok(results);
    }
}
