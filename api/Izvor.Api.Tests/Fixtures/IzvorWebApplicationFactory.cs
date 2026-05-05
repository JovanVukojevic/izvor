using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace Izvor.Api.Tests.Fixtures;

public sealed class IzvorWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string TestClientIpHeader = "X-Test-Client-Ip";

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

        // TestServer sets HttpContext.Connection.RemoteIpAddress to null, which
        // breaks any partition keyed on it (rate limiter) and stops the real
        // UseForwardedHeaders from rewriting (CheckKnownAddress(null) returns
        // false). Inject a startup filter that sets RemoteIpAddress from a
        // dedicated test header (or loopback fallback) before any other
        // middleware sees the request — equivalent to what UseForwardedHeaders
        // would do in production behind a trusted proxy.
        builder.ConfigureServices(services =>
        {
            services.TryAddEnumerable(
                ServiceDescriptor.Transient<Microsoft.AspNetCore.Hosting.IStartupFilter, TestClientIpStartupFilter>());
        });
    }

    private sealed class TestClientIpStartupFilter : Microsoft.AspNetCore.Hosting.IStartupFilter
    {
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
        {
            return app =>
            {
                app.Use(async (context, n) =>
                {
                    if (context.Request.Headers.TryGetValue(TestClientIpHeader, out var raw)
                        && IPAddress.TryParse(raw.ToString(), out var parsed))
                    {
                        context.Connection.RemoteIpAddress = parsed;
                    }
                    else if (context.Connection.RemoteIpAddress is null)
                    {
                        context.Connection.RemoteIpAddress = IPAddress.Loopback;
                    }
                    await n();
                });
                next(app);
            };
        }
    }
}
