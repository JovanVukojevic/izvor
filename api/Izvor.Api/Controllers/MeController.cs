using Izvor.Api.Database;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class MeController : ControllerBase
{
    private readonly IDbAccess _db;

    public MeController(IDbAccess db)
    {
        _db = db;
    }

    [HttpGet("me")]
    public async Task<IActionResult> GetAsync(CancellationToken cancellationToken)
    {
        var row = await _db.CallAsync<MeRow>("api.get_current_user", cancellationToken: cancellationToken);
        if (row is null)
        {
            return Unauthorized(new ErrorResponse(
                "user_no_longer_valid",
                "Current user no longer exists"));
        }

        return Ok(new UserInfo(
            row.Id,
            row.Email,
            row.Role,
            new TenantInfo(row.TenantId, row.TenantName, row.TenantSubdomain)));
    }

    // api.get_current_user returns api.user_with_tenant (flat columns); Dapper
    // doesn't flatten composite columns into nested DTOs natively, so this
    // intermediate record maps the row before the controller assembles UserInfo.
    private sealed record MeRow(
        Guid Id,
        string Email,
        string Role,
        Guid TenantId,
        string TenantName,
        string TenantSubdomain);
}
