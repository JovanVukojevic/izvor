using Izvor.Api.Dtos;
using Izvor.Api.Mapping;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/users")]
[Authorize]
public sealed class UsersController : ControllerBase
{
    private readonly IDbSessionContext _session;

    public UsersController(IDbSessionContext session)
    {
        _session = session;
    }

    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<UserResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IEnumerable<UserResponse>>> ListAsync(
        [FromQuery] ListUsersQuery query,
        CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {UserRowMapper.UserSelectColumns} FROM api.list_users(@roleFilter, @activeFilter)");
        command.Parameters.AddWithValue("roleFilter", (object?)query.Role ?? DBNull.Value);
        command.Parameters.AddWithValue("activeFilter", (object?)query.IsActive ?? DBNull.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var results = new List<UserResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(UserRowMapper.Map(reader));
        }
        return Ok(results);
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(UserResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<UserResponse>> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {UserRowMapper.UserSelectColumns} FROM api.get_user(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return NotFound(new ErrorResponse("not_found", "user_not_found"));
        }
        return Ok(UserRowMapper.Map(reader));
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

        Guid id;
        await using (var insertCommand = _session.CreateCommand(
            "SELECT api.create_user(@email, @hash, @role)"))
        {
            insertCommand.Parameters.AddWithValue("email", request.Email);
            insertCommand.Parameters.AddWithValue("hash", passwordHash);
            insertCommand.Parameters.AddWithValue("role", request.Role);
            id = (Guid)(await insertCommand.ExecuteScalarAsync(cancellationToken))!;
        }

        var created = await ReadUserAsync(id, cancellationToken);
        return Created($"/api/users/{id}", created);
    }

    [HttpPost("{id:guid}/deactivate")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeactivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.deactivate_user(@id)");
        command.Parameters.AddWithValue("id", id);
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    [HttpPost("{id:guid}/activate")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ActivateAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand("SELECT api.activate_user(@id)");
        command.Parameters.AddWithValue("id", id);
        await command.ExecuteScalarAsync(cancellationToken);
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

        await using var command = _session.CreateCommand(
            "SELECT api.admin_reset_password(@id, @hash)");
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("hash", passwordHash);
        await command.ExecuteScalarAsync(cancellationToken);
        return NoContent();
    }

    private async Task<UserResponse> ReadUserAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            $"SELECT {UserRowMapper.UserSelectColumns} FROM api.get_user(@id)");
        command.Parameters.AddWithValue("id", id);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                $"User {id} disappeared after creation — RLS or transaction issue");
        }
        return UserRowMapper.Map(reader);
    }
}
