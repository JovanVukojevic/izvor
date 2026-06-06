namespace Izvor.Api.Dtos;

public sealed record CreateCourseRequest(
    string Title,
    string? Description,
    Guid? CategoryId,
    string FirstLessonTitle,
    string FirstLessonContent);
