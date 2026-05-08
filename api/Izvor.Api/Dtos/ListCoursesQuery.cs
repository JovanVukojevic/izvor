namespace Izvor.Api.Dtos;

public sealed record ListCoursesQuery(Guid? CategoryId, string? Status, bool? Active);
