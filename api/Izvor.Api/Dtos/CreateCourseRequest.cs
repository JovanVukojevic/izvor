namespace Izvor.Api.Dtos;

public sealed record CreateCourseRequest(
    string Title,
    string? Description,
    Guid[] CategoryIds,
    string FirstLessonTitle,
    string FirstLessonContent);
