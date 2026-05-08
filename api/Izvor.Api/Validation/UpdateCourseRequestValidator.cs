using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class UpdateCourseRequestValidator : AbstractValidator<UpdateCourseRequest>
{
    public UpdateCourseRequestValidator()
    {
        // mirrors impl.courses.title CHECK length(trim(title)) BETWEEN 1 AND 300
        RuleFor(x => x.Title)
            .NotEmpty().WithMessage("Title is required")
            .Must(t => t is not null && t.Trim().Length >= 1 && t.Trim().Length <= 300)
            .WithMessage("Title must be between 1 and 300 characters after trimming");
    }
}
