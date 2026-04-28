using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class EnrollUserRequestValidator : AbstractValidator<EnrollUserRequest>
{
    public EnrollUserRequestValidator()
    {
        RuleFor(x => x.CourseId).NotEmpty();
        RuleFor(x => x.UserId).NotEmpty();
    }
}
