namespace Izvor.Api.Models;

public sealed record LoginResponse(string AccessToken, UserInfo User);
