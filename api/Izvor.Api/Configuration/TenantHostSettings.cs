namespace Izvor.Api.Configuration;

public sealed class TenantHostSettings
{
    public const string SectionName = "TenantHost";

    public required string BaseDomain { get; init; }
}
