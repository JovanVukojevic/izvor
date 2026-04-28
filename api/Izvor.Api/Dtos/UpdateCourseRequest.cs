namespace Izvor.Api.Dtos;

public sealed record UpdateCourseRequest(
    string Title,
    string? Description,
    Guid? CategoryId,
    bool Sequential);
