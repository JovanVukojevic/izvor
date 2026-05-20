using System.Text.RegularExpressions;
using Izvor.Api.Dtos;
using Npgsql;

namespace Izvor.Api.Errors;

// Centralized mapping of PostgresException → (HTTP status, ErrorResponse).
// The application-level `error` field is what clients switch on; `message`
// carries the original PG text verbatim for debuggability.
//
// Note: BOOLEAN-returning api functions whose `false` means "not found"
// (api.update_category, api.delete_category) are mapped to 404 by the
// CONTROLLER, not here. This mapper covers the exception path; controllers
// cover the boolean path. Both are part of the same status-code contract.
public static class ApiErrorMapper
{
    private static readonly HashSet<string> NotFoundCodes = new(StringComparer.Ordinal)
    {
        "course_not_found",
        "lesson_not_found",
        "enrollment_not_found",
        "user_not_found",
        "category_not_found"
    };

    private static readonly HashSet<string> StateInvalidCodes = new(StringComparer.Ordinal)
    {
        "course_inactive",
        "course_has_enrollments",
        "course_has_no_lessons",
        "lesson_has_progress",
        "enrollment_not_active",
        "enrollment_cancelled",
        "not_enrolled"
    };

    private static readonly HashSet<string> AlreadyExistsCodes = new(StringComparer.Ordinal)
    {
        "enrollment_already_active"
    };

    private static readonly HashSet<string> ForbiddenCodes = new(StringComparer.Ordinal)
    {
        "not_course_owner",
        "not_authorized",
        "no_active_user_in_session",
        "cannot_deactivate_self"
    };

    private static readonly HashSet<string> AccountInactiveCodes = new(StringComparer.Ordinal)
    {
        "user_inactive"
    };

    private static readonly HashSet<string> BadRequestCodes = new(StringComparer.Ordinal)
    {
        "position_out_of_range"
    };

    private static readonly HashSet<string> ValidationFailedCodes = new(StringComparer.Ordinal)
    {
        "category_required"
    };

    private static readonly HashSet<string> UnauthorizedCodes = new(StringComparer.Ordinal)
    {
        "invalid_refresh_token"
    };

    // Matches `spec.assert_role` raises like "role admin required, caller has learner".
    private static readonly Regex RoleRequiredPattern = new(
        @"^role .* required",
        RegexOptions.Compiled);

    // Older migrations (002/006/010) use verbose human-readable RAISE EXCEPTION
    // strings instead of snake_case codes. These patterns catch them so they
    // map to sensible status codes — uniqueness, in particular, is reachable
    // from valid (FV-passing) input. See plan §1 coverage audit.
    private static readonly Regex AlreadyExistsPattern = new(
        @"already exists",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex IsRequiredPattern = new(
        @" is required$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex InvalidDataPattern = new(
        @"^Invalid .* data:",
        RegexOptions.Compiled);

    public static (int StatusCode, ErrorResponse Body) Map(PostgresException ex)
    {
        var text = ex.MessageText;

        if (NotFoundCodes.Contains(text))
            return (StatusCodes.Status404NotFound, new ErrorResponse("not_found", text));

        if (StateInvalidCodes.Contains(text))
            return (StatusCodes.Status409Conflict, new ErrorResponse("state_invalid", text));

        if (AlreadyExistsCodes.Contains(text))
            return (StatusCodes.Status409Conflict, new ErrorResponse("already_exists", text));

        if (ForbiddenCodes.Contains(text))
            return (StatusCodes.Status403Forbidden, new ErrorResponse("forbidden", text));

        if (AccountInactiveCodes.Contains(text))
            return (StatusCodes.Status403Forbidden, new ErrorResponse("account_inactive", text));

        if (BadRequestCodes.Contains(text))
            return (StatusCodes.Status400BadRequest, new ErrorResponse("bad_request", text));

        if (ValidationFailedCodes.Contains(text))
            return (StatusCodes.Status400BadRequest, new ErrorResponse("validation_failed", text));

        if (UnauthorizedCodes.Contains(text))
            return (StatusCodes.Status401Unauthorized, new ErrorResponse("unauthorized", text));

        if (RoleRequiredPattern.IsMatch(text))
            return (StatusCodes.Status403Forbidden, new ErrorResponse("forbidden", text));

        if (AlreadyExistsPattern.IsMatch(text))
            return (StatusCodes.Status409Conflict, new ErrorResponse("already_exists", text));

        if (IsRequiredPattern.IsMatch(text) || InvalidDataPattern.IsMatch(text))
            return (StatusCodes.Status400BadRequest, new ErrorResponse("validation_failed", text));

        // SQLSTATE fallbacks for cases where a procedure didn't write a snake_case code,
        // or where the constraint engine itself fired (e.g. unique_violation outside an
        // EXCEPTION block).
        switch (ex.SqlState)
        {
            case "23505": // unique_violation
                return (StatusCodes.Status409Conflict, new ErrorResponse("already_exists", text));
            case "23503": // foreign_key_violation
                return (StatusCodes.Status409Conflict, new ErrorResponse("constraint_violation", text));
            case "23514": // check_violation
                return (StatusCodes.Status400BadRequest, new ErrorResponse("validation_failed", text));
            case "22P02": // invalid_text_representation (defense-in-depth for ENUM casts)
                return (StatusCodes.Status400BadRequest, new ErrorResponse("bad_request", text));
        }

        return (StatusCodes.Status500InternalServerError,
                new ErrorResponse("internal_error", "An unexpected database error occurred"));
    }
}
