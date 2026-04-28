using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Hosting;

namespace Izvor.Api.Tests.Fixtures;

public sealed class IzvorWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _connectionString;

    public IzvorWebApplicationFactory(string connectionString)
    {
        _connectionString = connectionString;
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        // Program.cs reads ConnectionStrings:Default during top-level statements,
        // which run BEFORE ConfigureWebHost callbacks fire. The only override
        // path that wins that race is environment variables, which the default
        // configuration sources read at builder construction time.
        Environment.SetEnvironmentVariable("ConnectionStrings__Default", _connectionString);
        return base.CreateHost(builder);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
    }
}
