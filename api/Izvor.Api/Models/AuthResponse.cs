namespace Izvor.Api.Models;

public sealed record AuthResponse(string AccessToken, UserInfo User);
