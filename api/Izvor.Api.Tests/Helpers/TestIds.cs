namespace Izvor.Api.Tests.Helpers;

public static class TestIds
{
    public static readonly Guid AcmeTenantId = new("11111111-1111-1111-1111-111111111111");
    public static readonly Guid IntellyaTenantId = new("22222222-2222-2222-2222-222222222222");

    public const string AcmeSubdomain = "acme";
    public const string IntellyaSubdomain = "intellya";

    public static readonly Guid MarkoUserId = new("aaaaaaaa-0000-0000-0000-000000000001");
    public static readonly Guid AnaUserId = new("aaaaaaaa-0000-0000-0000-000000000002");
    public static readonly Guid PeraUserId = new("aaaaaaaa-0000-0000-0000-000000000003");
    public static readonly Guid InactiveUserId = new("aaaaaaaa-0000-0000-0000-000000000004");

    public static readonly Guid JanaUserId = new("bbbbbbbb-0000-0000-0000-000000000001");
    public static readonly Guid PetarUserId = new("bbbbbbbb-0000-0000-0000-000000000002");

    public const string MarkoEmail = "marko@acme.test";
    public const string AnaEmail = "ana@acme.test";
    public const string PeraEmail = "pera@acme.test";
    public const string InactiveEmail = "inactive@acme.test";
    public const string JanaEmail = "jana@intellya.test";
    public const string PetarEmail = "petar@intellya.test";

    public const string TestPassword = "test123";
}
