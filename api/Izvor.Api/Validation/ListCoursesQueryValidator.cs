using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class ListCoursesQueryValidator : AbstractValidator<ListCoursesQuery>
{
    private static readonly string[] AllowedStatuses = { "draft", "published" };

    public ListCoursesQueryValidator()
    {
        // mirrors impl.course_status ENUM ('draft', 'published')
        // 22P02 (invalid_text_representation) is the defense-in-depth fallback in ApiErrorMapper.
        RuleFor(x => x.Status)
            .Must(s => s is null || AllowedStatuses.Contains(s))
            .WithMessage("Status must be one of: draft, published");
    }
}
