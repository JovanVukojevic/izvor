namespace Izvor.Api.Dtos;

public sealed record EnrollUserRequest(Guid CourseId, Guid UserId);
