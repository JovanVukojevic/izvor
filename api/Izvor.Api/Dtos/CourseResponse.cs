namespace Izvor.Api.Dtos;

// Property-based record (not positional) so Dapper materializes via parameterless
// constructor + property setters rather than constructor-argument matching. Npgsql
// reports Guid[] (uuid[]) columns with a generic System.Array reader type, which
// makes Dapper's exact-type constructor lookup fail on positional records.
public sealed record CourseResponse
{
    public Guid Id { get; init; }
    public Guid[] CategoryIds { get; init; } = Array.Empty<Guid>();
    public Guid AuthorId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string? Description { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
    public bool IsActive { get; init; }
}
