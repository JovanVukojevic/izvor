using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/users")]
[Authorize]
public sealed class UsersController : ControllerBase
{
    private readonly IDbAccess _db;

    public UsersController(IDbAccess db)
    {
        _db = db;
    }

    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<UserResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IEnumerable<UserResponse>>> ListAsync(
        [FromQuery] ListUsersQuery query,
        CancellationToken cancellationToken)
    {
        var results = await _db.QueryAsync<UserResponse>(
            "api.list_users",
            new { p_role_filter = query.Role, p_active_filter = query.IsActive },
            cancellationToken);
        return Ok(results);
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(UserResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<UserResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var user = await _db.CallAsync<UserResponse>(
            "api.get_user",
            new { p_id = id },
            cancellationToken);

        if (user is null)
        {
            return NotFound(new ErrorResponse("not_found", "user_not_found"));
        }
        return Ok(user);
    }

    [HttpPost]
    [ProducesResponseType(typeof(UserResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<UserResponse>> CreateAsync(
        [FromBody] CreateUserRequest request,
        CancellationToken cancellationToken)
    {
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);

        var created = await _db.CallAsync<UserResponse>(
            "api.create_user",
            new { p_email = request.Email, p_password_hash = passwordHash, p_role = request.Role },
            cancellationToken)
            ?? throw new InvalidOperationException("api.create_user returned no row");

        return Created($"/api/users/{created.Id}", created);
    }

    [HttpPost("{id:guid}/deactivate")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeactivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.deactivate_user",
            new { p_user_id = id },
            cancellationToken);
        return NoContent();
    }

    [HttpPost("{id:guid}/activate")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ActivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await _db.ExecuteAsync(
            "api.activate_user",
            new { p_user_id = id },
            cancellationToken);
        return NoContent();
    }

    [HttpPost("{id:guid}/reset-password")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ResetPasswordAsync(
        Guid id,
        [FromBody] AdminResetPasswordRequest request,
        CancellationToken cancellationToken)
    {
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);

        await _db.ExecuteAsync(
            "api.admin_reset_password",
            new { p_user_id = id, p_password_hash = passwordHash },
            cancellationToken);
        return NoContent();
    }
}
