using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading.RateLimiting;
using FluentValidation;
using Izvor.Api.Configuration;
using Izvor.Api.Middleware;
using Izvor.Api.Models;
using Izvor.Api.Services;
using Izvor.Api.Validation;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using SharpGrip.FluentValidation.AutoValidation.Mvc.Extensions;

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
builder.Services.AddScoped<IDbSessionContext, DbSessionContext>();

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

builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("login", httpContext =>
        RateLimitPartition.GetSlidingWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new SlidingWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromSeconds(60),
                SegmentsPerWindow = 6,
                QueueLimit = 0
            }));

    options.AddPolicy("refresh", httpContext =>
        RateLimitPartition.GetSlidingWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new SlidingWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromSeconds(60),
                SegmentsPerWindow = 6,
                QueueLimit = 0
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

app.UseCors("IzvorDevCors");
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseRateLimiter();
app.UseAuthentication();
app.UseMiddleware<JwtTenantMatchMiddleware>();
app.UseAuthorization();
app.UseMiddleware<DatabaseSessionContextMiddleware>();
app.UseMiddleware<PostgresExceptionHandlerMiddleware>();

app.MapOpenApi();
app.MapScalarApiReference();

app.MapControllers();

app.Run();
