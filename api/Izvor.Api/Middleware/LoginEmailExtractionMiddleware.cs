using System.Text.Json;

namespace Izvor.Api.Middleware;

public sealed class LoginEmailExtractionMiddleware
{
    public const string LoginEmailItemKey = "LoginEmail";

    private const string LoginPath = "/api/auth/login";
    private const int MaxBodyBytes = 1024;

    private readonly RequestDelegate _next;

    public LoginEmailExtractionMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!HttpMethods.IsPost(context.Request.Method)
            || !context.Request.Path.StartsWithSegments(LoginPath, StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        context.Request.EnableBuffering(bufferThreshold: MaxBodyBytes, bufferLimit: MaxBodyBytes);

        try
        {
            using var doc = await JsonDocument.ParseAsync(context.Request.Body, cancellationToken: context.RequestAborted);
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("email", out var emailEl)
                && emailEl.ValueKind == JsonValueKind.String)
            {
                var email = emailEl.GetString()?.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(email))
                {
                    context.Items[LoginEmailItemKey] = email;
                }
            }
        }
        catch (Exception ex) when (ex is JsonException
                                   or IOException
                                   or OperationCanceledException
                                   or InvalidOperationException
                                   or BadHttpRequestException)
        {
            // Swallow: partition lambda will fall back to NO_EMAIL:<ip>.
        }
        finally
        {
            if (context.Request.Body.CanSeek)
            {
                context.Request.Body.Position = 0;
            }
        }

        await _next(context);
    }
}
