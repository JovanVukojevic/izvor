using System.Text.Encodings.Web;
using System.Text.Json;
using Dapper;
using FluentValidation;
using Izvor.Api.Database;
using Izvor.Api.Extensions;
using Izvor.Api.Middleware;
using Izvor.Api.Services;
using Izvor.Api.Validation;
using Scalar.AspNetCore;
using SharpGrip.FluentValidation.AutoValidation.Mvc.Extensions;

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

builder.Services.AddIzvorOptions(builder.Configuration);
builder.Services.AddIzvorCors(builder.Configuration);

builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddScoped<IDbAccess, DbAccess>();
builder.Services.AddHttpContextAccessor();

builder.Services.AddIzvorAuthentication(builder.Configuration);
builder.Services.AddIzvorForwardedHeaders(builder.Configuration);
builder.Services.AddIzvorRateLimiting(jsonOptions);

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
