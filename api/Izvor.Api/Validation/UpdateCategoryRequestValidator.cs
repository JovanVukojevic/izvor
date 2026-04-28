using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class UpdateCategoryRequestValidator : AbstractValidator<UpdateCategoryRequest>
{
    public UpdateCategoryRequestValidator()
    {
        // mirrors impl.categories.name CHECK length(trim(name)) BETWEEN 1 AND 200
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Name is required")
            .Must(n => n is not null && n.Trim().Length >= 1 && n.Trim().Length <= 200)
            .WithMessage("Name must be between 1 and 200 characters after trimming");
    }
}
