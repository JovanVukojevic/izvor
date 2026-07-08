using Izvor.Api.Configuration;

namespace Izvor.Api.Extensions;

public static class CorsServiceExtensions
{
    public static IServiceCollection AddIzvorCors(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var corsSettings = configuration
            .GetSection(CorsSettings.SectionName)
            .Get<CorsSettings>()
            ?? throw new InvalidOperationException("Cors configuration section missing");

        var corsHostSuffix = "." + corsSettings.BaseDomain;

        services.AddCors(options =>
        {
            options.AddPolicy("IzvorDevCors", policy =>
            {
                policy.SetIsOriginAllowed(origin =>
                {
                    if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
                    {
                        return false;
                    }

                    if (string.IsNullOrEmpty(uri.Host))
                    {
                        return false;
                    }

                    return string.Equals(uri.Scheme, corsSettings.Scheme, StringComparison.OrdinalIgnoreCase)
                        && uri.Port == corsSettings.Port
                        && uri.Host.EndsWith(corsHostSuffix, StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(uri.Host, corsSettings.BaseDomain, StringComparison.OrdinalIgnoreCase);
                })
                .WithMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                .WithHeaders("Authorization", "Content-Type")
                .AllowCredentials();
            });
        });

        return services;
    }
}
