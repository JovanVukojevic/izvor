using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class CreateCourseRequestValidator : AbstractValidator<CreateCourseRequest>
{
    public CreateCourseRequestValidator()
    {
        // mirrors impl.courses.title CHECK length(trim(title)) BETWEEN 1 AND 300
        RuleFor(x => x.Title)
            .NotEmpty().WithMessage("Title is required")
            .Must(t => t is not null && t.Trim().Length >= 1 && t.Trim().Length <= 300)
            .WithMessage("Title must be between 1 and 300 characters after trimming");

        RuleFor(x => x.CategoryIds)
            .NotEmpty().WithMessage("Category is required");

        RuleFor(x => x.FirstLessonTitle)
            .NotEmpty().WithMessage("First lesson title is required")
            .Must(t => t is not null && t.Trim().Length >= 1 && t.Trim().Length <= 300)
            .WithMessage("First lesson title must be between 1 and 300 characters after trimming");

        RuleFor(x => x.FirstLessonContent)
            .NotNull().WithMessage("First lesson content is required");
    }
}
