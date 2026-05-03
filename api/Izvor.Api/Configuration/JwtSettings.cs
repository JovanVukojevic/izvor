namespace Izvor.Api.Configuration;

public sealed class JwtSettings
{
    public const string SectionName = "Jwt";

    public required string Issuer { get; init; }
    public required string Audience { get; init; }
    public required string SecretKey { get; init; }
    public required int AccessTokenLifetimeMinutes { get; init; }
    public required int RefreshTokenLifetimeDays { get; init; }
}
