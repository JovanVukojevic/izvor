using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace Izvor.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class HealthController : ControllerBase
{
    private readonly NpgsqlDataSource _dataSource;

    public HealthController(NpgsqlDataSource dataSource)
    {
        _dataSource = dataSource;
    }

    [HttpGet]
    public async Task<IActionResult> GetAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            var result = await command.ExecuteScalarAsync(cancellationToken);

            if (result is int value && value == 1)
            {
                return Ok(new { status = "healthy", database = "connected" });
            }

            return StatusCode(503, new { status = "unhealthy", database = "unexpected_result" });
        }
        catch (NpgsqlException)
        {
            return StatusCode(503, new { status = "unhealthy", database = "disconnected" });
        }
    }
}
