using Izvor.Api.Configuration;

namespace Izvor.Api.Extensions;

public static class OptionsServiceExtensions
{
    public static IServiceCollection AddIzvorOptions(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.Configure<JwtSettings>(
            configuration.GetSection(JwtSettings.SectionName));

        services.Configure<TenantHostSettings>(
            configuration.GetSection(TenantHostSettings.SectionName));

        services.Configure<CorsSettings>(
            configuration.GetSection(CorsSettings.SectionName));

        return services;
    }
}
