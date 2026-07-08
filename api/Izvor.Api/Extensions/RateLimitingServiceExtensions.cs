using System.Text.Json;
using System.Threading.RateLimiting;
using Izvor.Api.Dtos;
using Izvor.Api.Middleware;

namespace Izvor.Api.Extensions;

public static class RateLimitingServiceExtensions
{
    private const int GlobalPerIpPermitLimit = 100;
    private const int LoginPerIpPermitLimit = 5;
    private const int LoginPerUserPermitLimit = 10;
    private const int RefreshPerIpPermitLimit = 10;
    private const int RateLimitWindowSeconds = 60;
    private const int RateLimitSegmentsPerWindow = 6;
    private const string LoginPath = "/api/auth/login";
    private const string RefreshPath = "/api/auth/refresh";

    public static IServiceCollection AddIzvorRateLimiting(
        this IServiceCollection services,
        JsonSerializerOptions jsonOptions)
    {
        services.AddRateLimiter(options =>
        {
            options.GlobalLimiter = PartitionedRateLimiter.CreateChained(
                PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
                    RateLimitPartition.GetSlidingWindowLimiter(
                        partitionKey: "global-ip:" + (httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"),
                        factory: _ => new SlidingWindowRateLimiterOptions
                        {
                            PermitLimit = GlobalPerIpPermitLimit,
                            Window = TimeSpan.FromSeconds(RateLimitWindowSeconds),
                            SegmentsPerWindow = RateLimitSegmentsPerWindow,
                            QueueLimit = 0
                        })),

                PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
                {
                    if (!httpContext.Request.Path.StartsWithSegments(LoginPath, StringComparison.OrdinalIgnoreCase))
                    {
                        return RateLimitPartition.GetNoLimiter("none");
                    }
                    var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
                    return RateLimitPartition.GetSlidingWindowLimiter(
                        partitionKey: "login-ip:" + ip,
                        factory: _ => new SlidingWindowRateLimiterOptions
                        {
                            PermitLimit = LoginPerIpPermitLimit,
                            Window = TimeSpan.FromSeconds(RateLimitWindowSeconds),
                            SegmentsPerWindow = RateLimitSegmentsPerWindow,
                            QueueLimit = 0
                        });
                }),

                PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
                {
                    if (!httpContext.Request.Path.StartsWithSegments(LoginPath, StringComparison.OrdinalIgnoreCase))
                    {
                        return RateLimitPartition.GetNoLimiter("none");
                    }
                    var subdomain = httpContext.TryGetTenant()?.Subdomain ?? "unknown-tenant";
                    var key = httpContext.Items.TryGetValue(LoginEmailExtractionMiddleware.LoginEmailItemKey, out var e)
                              && e is string email
                        ? "login-user:" + subdomain + ":" + email
                        : "login-user:NO_EMAIL:" + (httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown");
                    return RateLimitPartition.GetSlidingWindowLimiter(
                        partitionKey: key,
                        factory: _ => new SlidingWindowRateLimiterOptions
                        {
                            PermitLimit = LoginPerUserPermitLimit,
                            Window = TimeSpan.FromSeconds(RateLimitWindowSeconds),
                            SegmentsPerWindow = RateLimitSegmentsPerWindow,
                            QueueLimit = 0
                        });
                }),

                // Refresh per-IP — preserves the original refresh-burst guard.
                PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
                {
                    if (!httpContext.Request.Path.StartsWithSegments(RefreshPath, StringComparison.OrdinalIgnoreCase))
                    {
                        return RateLimitPartition.GetNoLimiter("none");
                    }
                    var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
                    return RateLimitPartition.GetSlidingWindowLimiter(
                        partitionKey: "refresh-ip:" + ip,
                        factory: _ => new SlidingWindowRateLimiterOptions
                        {
                            PermitLimit = RefreshPerIpPermitLimit,
                            Window = TimeSpan.FromSeconds(RateLimitWindowSeconds),
                            SegmentsPerWindow = RateLimitSegmentsPerWindow,
                            QueueLimit = 0
                        });
                }));

            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.OnRejected = async (context, cancellationToken) =>
            {
                context.HttpContext.Response.ContentType = "application/json";
                var retrySeconds = context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter)
                    ? (int)retryAfter.TotalSeconds
                    : 10;
                context.HttpContext.Response.Headers.RetryAfter = retrySeconds.ToString();

                var payload = new ErrorResponse(
                    "rate_limit_exceeded",
                    "Too many requests. Please try again later.");
                await JsonSerializer.SerializeAsync(
                    context.HttpContext.Response.Body,
                    payload,
                    jsonOptions,
                    cancellationToken);
            };
        });

        return services;
    }
}
