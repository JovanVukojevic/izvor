using Izvor.Api.Extensions;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/tenant-info")]
public sealed class TenantInfoController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        var tenant = HttpContext.GetTenant();
        return Ok(tenant);
    }
}
