using FluentValidation;
using FluentValidation.Results;
using Izvor.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using SharpGrip.FluentValidation.AutoValidation.Mvc.Results;

namespace Izvor.Api.Validation;

// Returns ErrorResponse("validation_failed", message) where message is a
// concatenated human-readable summary of all FV failures, joined by ". ".
//
// Intentional limitation: no per-field structured error data. The Phase 4.2
// ErrorResponse(string error, string message) contract is preserved as-is
// project-wide. If the Angular UI in Phase 7.5+ needs field-level error
// highlighting for inline form feedback, the contract can be extended with
// an optional Dictionary<string, string[]>? errors field at that point.
// Concatenated messages are sufficient for 7.4a's clients (Scalar UI debugging
// + integration test assertions).
public sealed class IzvorProblemDetailsFactory : IFluentValidationAutoValidationResultFactory
{
    public Task<IActionResult?> CreateActionResult(
        ActionExecutingContext context,
        ValidationProblemDetails validationProblemDetails,
        IDictionary<IValidationContext, ValidationResult> validationResults)
    {
        var messages = validationResults.Values
            .SelectMany(r => r.Errors)
            .Select(e => e.ErrorMessage.TrimEnd('.'))
            .Where(m => !string.IsNullOrWhiteSpace(m))
            .ToArray();

        var summary = messages.Length == 0
            ? "Request failed validation."
            : string.Join(". ", messages) + ".";

        IActionResult? result = new BadRequestObjectResult(
            new ErrorResponse("validation_failed", summary));

        return Task.FromResult<IActionResult?>(result);
    }
}
