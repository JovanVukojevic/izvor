// REMOVE BEFORE DEFENSE
// Development-only endpoint for generating bcrypt hashes during Phase 4 testing.
// Tracked in diplomski-plan.md sekcija 14.1.

using Izvor.Api.Models;
using Microsoft.AspNetCore.Mvc;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/dev")]
[ApiExplorerSettings(IgnoreApi = true)]
[Obsolete("Dev-only endpoint. Must be removed before defense.")]
public sealed class DevController : ControllerBase
{
    [HttpPost("hash-password")]
    public IActionResult HashPassword([FromBody] HashPasswordRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new ErrorResponse(
                "invalid_input",
                "Password is required"));
        }

        var hash = BCrypt.Net.BCrypt.HashPassword(request.Password);
        return Ok(new HashPasswordResponse(hash));
    }
}
