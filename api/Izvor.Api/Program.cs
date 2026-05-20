using System.Net;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading.RateLimiting;
using Dapper;
using FluentValidation;
using Izvor.Api.Configuration;
using Izvor.Api.Database;
using Izvor.Api.Extensions;
using Izvor.Api.Middleware;
using Izvor.Api.Dtos;
using Izvor.Api.Services;
using Izvor.Api.Validation;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using SharpGrip.FluentValidation.AutoValidation.Mvc.Extensions;

const int GlobalPerIpPermitLimit = 100;
const int LoginPerIpPermitLimit = 5;
const int LoginPerUserPermitLimit = 10;
const int RefreshPerIpPermitLimit = 10;
const int RateLimitWindowSeconds = 60;
const int RateLimitSegmentsPerWindow = 6;
const string LoginPath = "/api/auth/login";
const string RefreshPath = "/api/auth/refresh";

DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);

var jsonOptions = new JsonSerializerOptions
{
    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
};
builder.Services.AddSingleton(jsonOptions);

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping;
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    });
builder.Services.AddOpenApi();

builder.Services.AddValidatorsFromAssemblyContaining<Program>();
builder.Services.AddFluentValidationAutoValidation(config =>
{
    config.OverrideDefaultResultFactoryWith<IzvorProblemDetailsFactory>();
});

var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("Connection string 'Default' not configured");
builder.Services.AddNpgsqlDataSource(connectionString);

builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection(JwtSettings.SectionName));

builder.Services.Configure<TenantHostSettings>(
    builder.Configuration.GetSection(TenantHostSettings.SectionName));

builder.Services.Configure<CorsSettings>(
    builder.Configuration.GetSection(CorsSettings.SectionName));

var corsSettings = builder.Configuration
    .GetSection(CorsSettings.SectionName)
    .Get<CorsSettings>()
    ?? throw new InvalidOperationException("Cors configuration section missing");

var corsHostSuffix = "." + corsSettings.BaseDomain;

builder.Services.AddCors(options =>
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

builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddScoped<IDbAccess, DbAccess>();
builder.Services.AddHttpContextAccessor();

var jwtSettings = builder.Configuration
    .GetSection(JwtSettings.SectionName)
    .Get<JwtSettings>()
    ?? throw new InvalidOperationException("Jwt configuration section missing");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings.Issuer,
            ValidAudience = jwtSettings.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtSettings.SecretKey)),
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

// X-Forwarded-For support is OFF by default. Enabling BehindProxy=true WITHOUT
// populating TrustedProxies is a header-spoofing vulnerability — any client could
// inject an X-Forwarded-For value to dodge per-IP rate limits. The whitelist
// below clears the framework's localhost defaults and only trusts what's
// explicitly configured.
var behindProxy = builder.Configuration.GetValue<bool>("BehindProxy");
if (behindProxy)
{
    var trustedProxies = builder.Configuration
        .GetSection("TrustedProxies")
        .Get<string[]>() ?? Array.Empty<string>();

    builder.Services.Configure<ForwardedHeadersOptions>(options =>
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
}

builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.CreateChained(
        // Universal per-IP cap — every request to every endpoint.
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

        // Login per-IP — preserves the original brute-force-resistant behavior.
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

        // Login per-user — caps brute force against a single account regardless
        // of source IP. Email is extracted by LoginEmailExtractionMiddleware
        // before this limiter runs; missing-email path falls back to a per-IP
        // bucket so attackers can't bypass via malformed JSON.
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

var app = builder.Build();

if (app.Configuration.GetValue<bool>("BehindProxy"))
{
    app.UseForwardedHeaders();
}

app.UseCors("IzvorDevCors");
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseMiddleware<LoginEmailExtractionMiddleware>();
app.UseRateLimiter();
app.UseAuthentication();
app.UseMiddleware<JwtTenantMatchMiddleware>();
app.UseAuthorization();
app.UseMiddleware<PostgresExceptionHandlerMiddleware>();

app.MapOpenApi();
app.MapScalarApiReference();

app.MapControllers();

app.Run();
