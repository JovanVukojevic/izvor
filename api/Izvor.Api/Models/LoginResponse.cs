namespace Izvor.Api.Models;

public sealed record LoginResponse(string Token, UserInfo User);
