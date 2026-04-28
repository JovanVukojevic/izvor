using Izvor.Api.Tests.Helpers;
using Npgsql;

namespace Izvor.Api.Tests.Fixtures;

// Seeds tenants and users via direct INSERTs as izvor_admin (bypasses RLS).
// Seeds are preconditions for tests, not under test — going through the api
// layer (api.create_user, system_api.create_tenant_with_admin) would couple
// fixture integrity to the very procedures the tests are exercising.
internal static class TestSeed
{
    public static async Task SeedAsync(string adminConnectionString)
    {
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(TestIds.TestPassword);

        await using var conn = new NpgsqlConnection(adminConnectionString);
        await conn.OpenAsync();

        await using var tx = await conn.BeginTransactionAsync();

        await InsertTenantAsync(conn, tx, TestIds.AcmeTenantId, "Acme Corp", "ACME", TestIds.AcmeSubdomain);
        await InsertTenantAsync(conn, tx, TestIds.IntellyaTenantId, "Intellya", "INTELLYA", TestIds.IntellyaSubdomain);

        await InsertUserAsync(conn, tx, TestIds.MarkoUserId, TestIds.AcmeTenantId, TestIds.MarkoEmail, passwordHash, "admin", true);
        await InsertUserAsync(conn, tx, TestIds.AnaUserId, TestIds.AcmeTenantId, TestIds.AnaEmail, passwordHash, "author", true);
        await InsertUserAsync(conn, tx, TestIds.PeraUserId, TestIds.AcmeTenantId, TestIds.PeraEmail, passwordHash, "learner", true);
        await InsertUserAsync(conn, tx, TestIds.IvanaUserId, TestIds.AcmeTenantId, TestIds.IvanaEmail, passwordHash, "learner", true);
        await InsertUserAsync(conn, tx, TestIds.InactiveUserId, TestIds.AcmeTenantId, TestIds.InactiveEmail, passwordHash, "learner", false);

        await InsertUserAsync(conn, tx, TestIds.JanaUserId, TestIds.IntellyaTenantId, TestIds.JanaEmail, passwordHash, "admin", true);
        await InsertUserAsync(conn, tx, TestIds.PetarUserId, TestIds.IntellyaTenantId, TestIds.PetarEmail, passwordHash, "author", true);

        await tx.CommitAsync();
    }

    private static async Task InsertTenantAsync(
        NpgsqlConnection conn, NpgsqlTransaction tx,
        Guid id, string name, string code, string subdomain)
    {
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO system_impl.tenants (id, name, code, subdomain, status) " +
            "VALUES (@id, @name, @code, @subdomain, 'active')",
            conn, tx);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("name", name);
        cmd.Parameters.AddWithValue("code", code);
        cmd.Parameters.AddWithValue("subdomain", subdomain);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task InsertUserAsync(
        NpgsqlConnection conn, NpgsqlTransaction tx,
        Guid id, Guid tenantId, string email, string passwordHash, string role, bool isActive)
    {
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO impl.users (id, tenant_id, email, password_hash, role, is_active) " +
            "VALUES (@id, @tenantId, @email, @passwordHash, @role::impl.user_role, @isActive)",
            conn, tx);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("tenantId", tenantId);
        cmd.Parameters.AddWithValue("email", email);
        cmd.Parameters.AddWithValue("passwordHash", passwordHash);
        cmd.Parameters.AddWithValue("role", role);
        cmd.Parameters.AddWithValue("isActive", isActive);
        await cmd.ExecuteNonQueryAsync();
    }

    public static async Task ResetCategoriesAndCoursesAsync(string adminConnectionString)
    {
        await using var conn = new NpgsqlConnection(adminConnectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand(
            "TRUNCATE impl.lesson_progress, impl.enrollments, impl.lessons, impl.courses, impl.categories CASCADE",
            conn);
        await cmd.ExecuteNonQueryAsync();
    }
}
