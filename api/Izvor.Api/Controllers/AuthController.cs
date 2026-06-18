using Izvor.Api.Configuration;
using Izvor.Api.Database;
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

    private readonly IDbAccess _db;
    private readonly IJwtTokenService _tokenService;
    private readonly JwtSettings _jwtSettings;

    public AuthController(
        IDbAccess db,
        IJwtTokenService tokenService,
        IOptions<JwtSettings> jwtSettings)
    {
        _db = db;
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

        LoginResult result;
        try
        {
            result = await _db.InTransactionAsync(async scope =>
            {
                await scope.SetTenantAsync(tenant.Id, cancellationToken);

                var credentials = await scope.CallAsync<CredentialsRow>(
                    "api.authenticate_user",
                    new { p_email = request.Email },
                    cancellationToken);

                if (credentials is null || !TryVerifyPassword(request.Password, credentials.PasswordHash))
                {
                    throw new AuthFailedException();
                }

                await scope.SetUserAsync(credentials.Id, cancellationToken);

                var refresh = await scope.CallAsync<RefreshTokenRow>(
                    "api.create_refresh_token",
                    new { p_days = _jwtSettings.RefreshTokenLifetimeDays },
                    cancellationToken)
                    ?? throw new InvalidOperationException("api.create_refresh_token returned no row");

                return new LoginResult(
                    credentials.Id, credentials.Email, credentials.Role, refresh.Token, refresh.ExpiresAt);
            }, cancellationToken);
        }
        catch (AuthFailedException)
        {
            return Unauthorized(InvalidCredentials);
        }

        AppendRefreshCookie(result.RefreshToken, result.RefreshExpiresAt);

        var accessToken = _tokenService.GenerateToken(result.UserId, tenant.Id, result.Role, result.Email);
        var userInfo = new UserInfo(
            Id: result.UserId,
            Email: result.Email,
            Role: result.Role,
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

        RefreshResult result;
        try
        {
            result = await _db.InTransactionAsync(async scope =>
            {
                await scope.SetTenantAsync(tenant.Id, cancellationToken);

                var rotated = await scope.CallAsync<RefreshTokenRow>(
                    "api.rotate_refresh_token",
                    new { p_token = incomingToken, p_days = _jwtSettings.RefreshTokenLifetimeDays },
                    cancellationToken)
                    ?? throw new InvalidOperationException("api.rotate_refresh_token returned no row");

                await scope.SetUserAsync(rotated.UserId, cancellationToken);

                var user = await scope.CallAsync<CurrentUserRow>(
                    "api.get_current_user",
                    cancellationToken: cancellationToken)
                    ?? throw new RefreshUserMissingException();

                return new RefreshResult(user, rotated.Token, rotated.ExpiresAt);
            }, cancellationToken);
        }
        catch (PostgresException ex) when (ex.MessageText == "invalid_refresh_token")
        {
            AppendClearingRefreshCookie();
            return Unauthorized(InvalidRefreshToken);
        }
        catch (RefreshUserMissingException)
        {
            AppendClearingRefreshCookie();
            return Unauthorized(InvalidRefreshToken);
        }

        AppendRefreshCookie(result.RefreshToken, result.RefreshExpiresAt);

        var accessToken = _tokenService.GenerateToken(
            result.User.Id, result.User.TenantId, result.User.Role, result.User.Email);
        var userInfo = new UserInfo(
            Id: result.User.Id,
            Email: result.User.Email,
            Role: result.User.Role,
            Tenant: new TenantInfo(result.User.TenantId, result.User.TenantName, result.User.TenantSubdomain));
        return Ok(new AuthResponse(accessToken, userInfo));
    }

    [HttpPost("logout")]
    public async Task<IActionResult> LogoutAsync(CancellationToken cancellationToken)
    {
        if (Request.Cookies.TryGetValue(RefreshCookieName, out var incomingToken)
            && !string.IsNullOrWhiteSpace(incomingToken))
        {
            var tenant = HttpContext.GetTenant();

            await _db.InTransactionAsync(async scope =>
            {
                await scope.SetTenantAsync(tenant.Id, cancellationToken);
                await scope.ExecuteAsync(
                    "api.revoke_refresh_token",
                    new { p_token = incomingToken },
                    cancellationToken);
            }, cancellationToken);
        }

        AppendClearingRefreshCookie();
        return NoContent();
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

    // Property-based records (not positional) so Dapper materializes via the
    // parameterless constructor + name-matched setters instead of exact-signature
    // constructor matching, which would fail because the api composite types carry
    // extra columns (e.g. created_at/updated_at) the controller doesn't need. Same
    // reason documented on Dtos/CourseResponse.
    private sealed record CredentialsRow
    {
        public Guid Id { get; init; }
        public string Email { get; init; } = string.Empty;
        public string PasswordHash { get; init; } = string.Empty;
        public string Role { get; init; } = string.Empty;
    }

    private sealed record CurrentUserRow
    {
        public Guid Id { get; init; }
        public string Email { get; init; } = string.Empty;
        public string Role { get; init; } = string.Empty;
        public Guid TenantId { get; init; }
        public string TenantName { get; init; } = string.Empty;
        public string TenantSubdomain { get; init; } = string.Empty;
    }

    private sealed record RefreshTokenRow
    {
        public Guid Id { get; init; }
        public Guid UserId { get; init; }
        public string Token { get; init; } = string.Empty;
        public DateTimeOffset IssuedAt { get; init; }
        public DateTimeOffset ExpiresAt { get; init; }
    }

    private sealed record LoginResult(
        Guid UserId,
        string Email,
        string Role,
        string RefreshToken,
        DateTimeOffset RefreshExpiresAt);

    private sealed record RefreshResult(
        CurrentUserRow User,
        string RefreshToken,
        DateTimeOffset RefreshExpiresAt);

    private sealed class AuthFailedException : Exception;

    private sealed class RefreshUserMissingException : Exception;
}
