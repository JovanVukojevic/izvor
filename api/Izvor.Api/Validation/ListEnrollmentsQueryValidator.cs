using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class ListEnrollmentsQueryValidator : AbstractValidator<ListEnrollmentsQuery>
{
    private static readonly string[] AllowedStatuses = { "active", "completed", "cancelled" };

    public ListEnrollmentsQueryValidator()
    {
        // mirrors impl.enrollment_status ENUM ('active', 'completed', 'cancelled')
        // 22P02 (invalid_text_representation) is the defense-in-depth fallback in ApiErrorMapper.
        RuleFor(x => x.Status)
            .Must(s => s is null || AllowedStatuses.Contains(s))
            .WithMessage("Status must be one of: active, completed, cancelled");
    }
}
