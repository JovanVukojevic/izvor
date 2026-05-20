namespace Izvor.Api.Dtos;

public sealed record AuthResponse(string AccessToken, UserInfo User);
