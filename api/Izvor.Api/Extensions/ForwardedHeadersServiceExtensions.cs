using System.Net;
using Microsoft.AspNetCore.HttpOverrides;

namespace Izvor.Api.Extensions;

public static class ForwardedHeadersServiceExtensions
{
    public static IServiceCollection AddIzvorForwardedHeaders(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var behindProxy = configuration.GetValue<bool>("BehindProxy");
        if (!behindProxy)
        {
            return services;
        }

        var trustedProxies = configuration
            .GetSection("TrustedProxies")
            .Get<string[]>() ?? Array.Empty<string>();

        services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            options.ForwardLimit = 1;
            options.KnownProxies.Clear();
            options.KnownIPNetworks.Clear();
            foreach (var proxy in trustedProxies)
            {
                if (IPAddress.TryParse(proxy, out var ip))
                {
                    options.KnownProxies.Add(ip);
                }
            }
        });

        return services;
    }
}
