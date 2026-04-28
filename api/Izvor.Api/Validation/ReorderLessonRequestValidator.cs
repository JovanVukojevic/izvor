using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class ReorderLessonRequestValidator : AbstractValidator<ReorderLessonRequest>
{
    public ReorderLessonRequestValidator()
    {
        // upper bound is dynamic (lesson count per course); DB raises position_out_of_range.
        RuleFor(x => x.Position)
            .GreaterThanOrEqualTo(1).WithMessage("Position must be 1 or greater");
    }
}
