using Izvor.Api.Extensions;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Npgsql;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController : ControllerBase
{
    private static readonly ErrorResponse InvalidCredentials = new(
        "invalid_credentials",
        "Email or password is incorrect");

    private readonly NpgsqlDataSource _dataSource;
    private readonly IJwtTokenService _tokenService;

    public AuthController(NpgsqlDataSource dataSource, IJwtTokenService tokenService)
    {
        _dataSource = dataSource;
        _tokenService = tokenService;
    }

    [HttpPost("login")]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> LoginAsync(
        [FromBody] LoginRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
        {
            return Unauthorized(InvalidCredentials);
        }

        var tenant = HttpContext.GetTenant();

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var setCommand = new NpgsqlCommand(
            "SELECT set_config('app.current_tenant', @t, true)", connection, transaction))
        {
            setCommand.Parameters.AddWithValue("t", tenant.Id.ToString());
            await setCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        Guid userId = Guid.Empty;
        string email = string.Empty;
        string passwordHash = string.Empty;
        string role = string.Empty;
        bool userFound;

        await using (var authCommand = new NpgsqlCommand(
            "SELECT id, email, password_hash, role FROM api.authenticate_user(@email)",
            connection, transaction))
        {
            authCommand.Parameters.AddWithValue("email", request.Email);

            await using var reader = await authCommand.ExecuteReaderAsync(cancellationToken);
            userFound = await reader.ReadAsync(cancellationToken);
            if (userFound)
            {
                userId = reader.GetGuid(0);
                email = reader.GetString(1);
                passwordHash = reader.GetString(2);
                role = reader.GetString(3);
            }
        }

        if (!userFound || !TryVerifyPassword(request.Password, passwordHash))
        {
            await transaction.RollbackAsync(cancellationToken);
            return Unauthorized(InvalidCredentials);
        }

        await transaction.CommitAsync(cancellationToken);

        var token = _tokenService.GenerateToken(userId, tenant.Id, role, email);
        return Ok(new LoginResponse(token, new UserInfo(userId, email, role)));
    }

    private static bool TryVerifyPassword(string password, string hash)
    {
        try
        {
            return BCrypt.Net.BCrypt.Verify(password, hash);
        }
        catch (BCrypt.Net.SaltParseException)
        {
            return false;
        }
    }
}
