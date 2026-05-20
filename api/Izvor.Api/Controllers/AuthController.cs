using Izvor.Api.Configuration;
using Izvor.Api.Extensions;
using Izvor.Api.Dtos;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController : ControllerBase
{
    private const string RefreshCookieName = "refreshToken";
    private const string RefreshCookiePath = "/api/auth";

    private static readonly ErrorResponse InvalidCredentials = new(
        "invalid_credentials",
        "Email or password is incorrect");

    private static readonly ErrorResponse MissingRefreshToken = new(
        "unauthorized",
        "missing_refresh_token");

    private static readonly ErrorResponse InvalidRefreshToken = new(
        "unauthorized",
        "invalid_refresh_token");

    private readonly NpgsqlDataSource _dataSource;
    private readonly IJwtTokenService _tokenService;
    private readonly JwtSettings _jwtSettings;

    public AuthController(
        NpgsqlDataSource dataSource,
        IJwtTokenService tokenService,
        IOptions<JwtSettings> jwtSettings)
    {
        _dataSource = dataSource;
        _tokenService = tokenService;
        _jwtSettings = jwtSettings.Value;
    }

    [HttpPost("login")]
    [RequestSizeLimit(2048)]
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

        await SetConfigAsync(connection, transaction, "app.current_tenant", tenant.Id.ToString(), cancellationToken);

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

        await SetConfigAsync(connection, transaction, "app.current_user", userId.ToString(), cancellationToken);

        var refresh = await CreateRefreshTokenAsync(connection, transaction, cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        AppendRefreshCookie(refresh.Token, refresh.ExpiresAt);

        var accessToken = _tokenService.GenerateToken(userId, tenant.Id, role, email);
        var userInfo = new UserInfo(
            Id: userId,
            Email: email,
            Role: role,
            Tenant: new TenantInfo(tenant.Id, tenant.Name, tenant.Subdomain));
        return Ok(new AuthResponse(accessToken, userInfo));
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> RefreshAsync(CancellationToken cancellationToken)
    {
        if (!Request.Cookies.TryGetValue(RefreshCookieName, out var incomingToken)
            || string.IsNullOrWhiteSpace(incomingToken))
        {
            return Unauthorized(MissingRefreshToken);
        }

        var tenant = HttpContext.GetTenant();

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await SetConfigAsync(connection, transaction, "app.current_tenant", tenant.Id.ToString(), cancellationToken);

        RefreshTokenRow rotated;
        try
        {
            rotated = await RotateRefreshTokenAsync(connection, transaction, incomingToken!, cancellationToken);
        }
        catch (PostgresException ex) when (ex.MessageText == "invalid_refresh_token")
        {
            await transaction.RollbackAsync(cancellationToken);
            AppendClearingRefreshCookie();
            return Unauthorized(InvalidRefreshToken);
        }

        await SetConfigAsync(connection, transaction, "app.current_user", rotated.UserId.ToString(), cancellationToken);

        Guid userId = rotated.UserId;
        string email = string.Empty;
        string role = string.Empty;
        Guid tenantIdFromDb = Guid.Empty;
        string tenantName = string.Empty;
        string tenantSubdomain = string.Empty;
        bool userFound;

        await using (var meCommand = new NpgsqlCommand(
            "SELECT id, email, role, tenant_id, tenant_name, tenant_subdomain FROM api.get_current_user()",
            connection, transaction))
        {
            await using var reader = await meCommand.ExecuteReaderAsync(cancellationToken);
            userFound = await reader.ReadAsync(cancellationToken);
            if (userFound)
            {
                userId = reader.GetGuid(0);
                email = reader.GetString(1);
                role = reader.GetString(2);
                tenantIdFromDb = reader.GetGuid(3);
                tenantName = reader.GetString(4);
                tenantSubdomain = reader.GetString(5);
            }
        }

        if (!userFound)
        {
            await transaction.RollbackAsync(cancellationToken);
            AppendClearingRefreshCookie();
            return Unauthorized(InvalidRefreshToken);
        }

        await transaction.CommitAsync(cancellationToken);

        AppendRefreshCookie(rotated.Token, rotated.ExpiresAt);

        var accessToken = _tokenService.GenerateToken(userId, tenantIdFromDb, role, email);
        var userInfo = new UserInfo(
            Id: userId,
            Email: email,
            Role: role,
            Tenant: new TenantInfo(tenantIdFromDb, tenantName, tenantSubdomain));
        return Ok(new AuthResponse(accessToken, userInfo));
    }

    [HttpPost("logout")]
    public async Task<IActionResult> LogoutAsync(CancellationToken cancellationToken)
    {
        if (Request.Cookies.TryGetValue(RefreshCookieName, out var incomingToken)
            && !string.IsNullOrWhiteSpace(incomingToken))
        {
            var tenant = HttpContext.GetTenant();

            await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

            await SetConfigAsync(connection, transaction, "app.current_tenant", tenant.Id.ToString(), cancellationToken);

            await using (var revokeCommand = new NpgsqlCommand(
                "SELECT api.revoke_refresh_token(@token)", connection, transaction))
            {
                revokeCommand.Parameters.AddWithValue("token", incomingToken!);
                await revokeCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
        }

        AppendClearingRefreshCookie();
        return NoContent();
    }

    private async Task<RefreshTokenRow> CreateRefreshTokenAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT id, user_id, token, issued_at, expires_at FROM api.create_refresh_token(@days)",
            connection, transaction);
        command.Parameters.AddWithValue("days", _jwtSettings.RefreshTokenLifetimeDays);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("api.create_refresh_token returned no rows");
        }

        return new RefreshTokenRow(
            Id: reader.GetGuid(0),
            UserId: reader.GetGuid(1),
            Token: reader.GetString(2),
            IssuedAt: reader.GetFieldValue<DateTimeOffset>(3),
            ExpiresAt: reader.GetFieldValue<DateTimeOffset>(4));
    }

    private async Task<RefreshTokenRow> RotateRefreshTokenAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string incomingToken,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT id, user_id, token, issued_at, expires_at FROM api.rotate_refresh_token(@token, @days)",
            connection, transaction);
        command.Parameters.AddWithValue("token", incomingToken);
        command.Parameters.AddWithValue("days", _jwtSettings.RefreshTokenLifetimeDays);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("api.rotate_refresh_token returned no rows");
        }

        return new RefreshTokenRow(
            Id: reader.GetGuid(0),
            UserId: reader.GetGuid(1),
            Token: reader.GetString(2),
            IssuedAt: reader.GetFieldValue<DateTimeOffset>(3),
            ExpiresAt: reader.GetFieldValue<DateTimeOffset>(4));
    }

    private static async Task SetConfigAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string key,
        string value,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT set_config(@k, @v, true)", connection, transaction);
        command.Parameters.AddWithValue("k", key);
        command.Parameters.AddWithValue("v", value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private void AppendRefreshCookie(string token, DateTimeOffset expiresAt)
    {
        Response.Cookies.Append(RefreshCookieName, token, new CookieOptions
        {
            HttpOnly = true,
            Secure = Request.IsHttps,
            SameSite = SameSiteMode.Lax,
            Path = RefreshCookiePath,
            Expires = expiresAt
        });
    }

    private void AppendClearingRefreshCookie()
    {
        Response.Cookies.Append(RefreshCookieName, string.Empty, new CookieOptions
        {
            HttpOnly = true,
            Secure = Request.IsHttps,
            SameSite = SameSiteMode.Lax,
            Path = RefreshCookiePath,
            Expires = DateTimeOffset.UnixEpoch
        });
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

    private sealed record RefreshTokenRow(
        Guid Id,
        Guid UserId,
        string Token,
        DateTimeOffset IssuedAt,
        DateTimeOffset ExpiresAt);
}
