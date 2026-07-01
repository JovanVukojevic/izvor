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

        RuleFor(x => x.Lessons)
            .NotEmpty().WithMessage("At least one lesson is required");

        // mirrors impl.lessons.title CHECK length(trim(title)) BETWEEN 1 AND 300
        RuleForEach(x => x.Lessons).ChildRules(lesson =>
            lesson.RuleFor(l => l.Title)
                .NotEmpty().WithMessage("Lesson title is required")
                .Must(t => t is not null && t.Trim().Length >= 1 && t.Trim().Length <= 300)
                .WithMessage("Lesson title must be between 1 and 300 characters after trimming"));
    }
}
