using Izvor.Api.Models;
using Izvor.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api")]
[Authorize]
public sealed class MeController : ControllerBase
{
    private readonly IDbSessionContext _session;

    public MeController(IDbSessionContext session)
    {
        _session = session;
    }

    [HttpGet("me")]
    public async Task<IActionResult> GetAsync(CancellationToken cancellationToken)
    {
        await using var command = _session.CreateCommand(
            "SELECT id, email, role, tenant_id, tenant_name, tenant_subdomain FROM api.get_current_user()");

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return Unauthorized(new ErrorResponse(
                "user_no_longer_valid",
                "Current user no longer exists"));
        }

        var user = new UserInfo(
            Id: reader.GetGuid(0),
            Email: reader.GetString(1),
            Role: reader.GetString(2),
            Tenant: new TenantInfo(
                Id: reader.GetGuid(3),
                Name: reader.GetString(4),
                Subdomain: reader.GetString(5)));

        return Ok(user);
    }
}
