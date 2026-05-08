namespace Izvor.Api.Dtos;

public sealed record ListCoursesQuery(Guid? CategoryId, bool? Active);
