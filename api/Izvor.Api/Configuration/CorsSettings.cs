namespace Izvor.Api.Configuration;

public sealed class CorsSettings
{
    public const string SectionName = "Cors";

    public required string Scheme { get; init; }
    public required string BaseDomain { get; init; }
    public required int Port { get; init; }
}
