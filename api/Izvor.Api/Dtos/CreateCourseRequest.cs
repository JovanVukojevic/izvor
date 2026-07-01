namespace Izvor.Api.Dtos;

public sealed record CreateCourseRequest(
    string Title,
    string? Description,
    Guid[] CategoryIds,
    IReadOnlyList<CreateLessonInput> Lessons);

public sealed record CreateLessonInput(string Title, string? Content);
