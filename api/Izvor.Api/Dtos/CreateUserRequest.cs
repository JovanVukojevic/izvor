namespace Izvor.Api.Dtos;

public sealed record CreateUserRequest(string Email, string Password, string Role);
