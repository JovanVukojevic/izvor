using Izvor.Api.Dtos;
using Izvor.Api.Mapping;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/categories")]
[Authorize]
public sealed class CategoriesController : ControllerBase
{
    private readonly IDbSessionContext _session;

    public CategoriesController(IDbSessionContext session)
    {
        _session = session;
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
        Guid id;
        await using (var insertCommand = _session.CreateCommand(
            "SELECT api.create_category(@name, @description)"))
        {
            insertCommand.Parameters.AddWithValue("name", request.Name);
            insertCommand.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
            id = (Guid)(await insertCommand.ExecuteScalarAsync(cancellationToken))!;
        }

        var created = await ReadCategoryAsync(id, cancellationToken);
        return Created($"/api/categories/{id}", created);
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
        await using var command = _session.CreateCommand(
            "SELECT api.update_category(@id, @name, @description)");
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("name", request.Name);
        command.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);

        // spec.update_category has no pre-existence check, so RETURN FOUND from
        // the UPDATE means false → row didn't exist (under RLS).
        var result = (bool)(await command.ExecuteScalarAsync(cancellationToken))!;
        if (!result)
        {
            return NotFound(new ErrorResponse("not_found", "category_not_found"));
        }

        return NoContent();
    }

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.delete_category(@id)");
        command.Parameters.AddWithValue("id", id);

        var result = (bool)(await command.ExecuteScalarAsync(cancellationToken))!;
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
        var category = await TryReadCategoryAsync(id, cancellationToken);
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
        await using var command = _session.CreateCommand(
            "SELECT id, name, description, created_at, updated_at FROM api.list_categories()");

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<CategoryResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(CategoryRowMapper.Map(reader));
        }
        return Ok(results);
    }

    private async Task<CategoryResponse> ReadCategoryAsync(Guid id, CancellationToken cancellationToken)
    {
        var category = await TryReadCategoryAsync(id, cancellationToken)
            ?? throw new InvalidOperationException(
                $"Category {id} disappeared after creation — RLS or transaction issue");
        return category;
    }

    private async Task<CategoryResponse?> TryReadCategoryAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            "SELECT id, name, description, created_at, updated_at FROM api.get_category(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }
        return CategoryRowMapper.Map(reader);
    }
}
