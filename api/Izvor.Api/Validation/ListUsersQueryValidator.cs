using FluentValidation;
using Izvor.Api.Dtos;

namespace Izvor.Api.Validation;

public sealed class ListUsersQueryValidator : AbstractValidator<ListUsersQuery>
{
    // mirrors impl.user_role ENUM ('admin', 'author', 'learner')
    private static readonly string[] AllowedRoles = { "admin", "author", "learner" };

    public ListUsersQueryValidator()
    {
        RuleFor(x => x.Role)
            .Must(r => r is null || AllowedRoles.Contains(r))
            .WithMessage("Role must be one of: admin, author, learner");
    }
}
