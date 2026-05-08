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
        await SeedRolesForTenantAsync(conn, tx, TestIds.AcmeTenantId);

        await InsertTenantAsync(conn, tx, TestIds.IntellyaTenantId, "Intellya", "INTELLYA", TestIds.IntellyaSubdomain);
        await SeedRolesForTenantAsync(conn, tx, TestIds.IntellyaTenantId);

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

    private static async Task SeedRolesForTenantAsync(
        NpgsqlConnection conn, NpgsqlTransaction tx, Guid tenantId)
    {
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO impl.roles (tenant_id, code, name, description, rank) VALUES " +
            "(@tenantId, 'admin',   'Administrator', 'Full administrative access within the organization', 100), " +
            "(@tenantId, 'author',  'Author',        'Can create and manage course content',                50), " +
            "(@tenantId, 'learner', 'Learner',       'Can browse and complete courses',                     10)",
            conn, tx);
        cmd.Parameters.AddWithValue("tenantId", tenantId);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task InsertUserAsync(
        NpgsqlConnection conn, NpgsqlTransaction tx,
        Guid id, Guid tenantId, string email, string passwordHash, string role, bool isActive)
    {
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO impl.users (id, tenant_id, email, password_hash, role_id, is_active) " +
            "VALUES (@id, @tenantId, @email, @passwordHash, " +
            "        (SELECT id FROM impl.roles WHERE tenant_id = @tenantId AND code = @role), " +
            "        @isActive)",
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

    public static async Task ResetRefreshTokensAsync(string adminConnectionString)
    {
        await using var conn = new NpgsqlConnection(adminConnectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("TRUNCATE impl.refresh_tokens", conn);
        await cmd.ExecuteNonQueryAsync();
    }

    // Restores users to their canonical seeded state: removes user rows
    // outside the fixture list (cleanup of test-created users), resets
    // is_active flags, resets password_hash. Also clears refresh_tokens so
    // deactivate/reset-password tests can verify revocation against a
    // known-empty starting set.
    //
    // izvor_admin is subject to FORCE RLS, so DELETE/UPDATE on impl.users
    // and impl.refresh_tokens need app.current_tenant set. Run per tenant.
    public static async Task ResetUsersAsync(string adminConnectionString)
    {
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(TestIds.TestPassword);

        await using var conn = new NpgsqlConnection(adminConnectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();

        await ResetTenantAsync(conn, tx, TestIds.AcmeTenantId, passwordHash, new[]
        {
            TestIds.MarkoUserId, TestIds.AnaUserId, TestIds.PeraUserId,
            TestIds.IvanaUserId, TestIds.InactiveUserId
        }, TestIds.InactiveUserId);

        await ResetTenantAsync(conn, tx, TestIds.IntellyaTenantId, passwordHash, new[]
        {
            TestIds.JanaUserId, TestIds.PetarUserId
        }, inactiveId: null);

        await tx.CommitAsync();
    }

    private static async Task ResetTenantAsync(
        NpgsqlConnection conn, NpgsqlTransaction tx,
        Guid tenantId, string passwordHash, Guid[] fixtureUserIds, Guid? inactiveId)
    {
        await using (var setCfg = new NpgsqlCommand(
            "SELECT set_config('app.current_tenant', @t, true)", conn, tx))
        {
            setCfg.Parameters.AddWithValue("t", tenantId.ToString());
            await setCfg.ExecuteNonQueryAsync();
        }

        await using (var clearTokens = new NpgsqlCommand(
            "DELETE FROM impl.refresh_tokens", conn, tx))
        {
            await clearTokens.ExecuteNonQueryAsync();
        }

        await using (var deleteExtras = new NpgsqlCommand(
            "DELETE FROM impl.users WHERE id <> ALL(@ids)", conn, tx))
        {
            deleteExtras.Parameters.AddWithValue("ids", fixtureUserIds);
            await deleteExtras.ExecuteNonQueryAsync();
        }

        var sql = inactiveId.HasValue
            ? "UPDATE impl.users SET is_active = (id <> @inactive), password_hash = @hash"
            : "UPDATE impl.users SET is_active = TRUE, password_hash = @hash";
        await using var resetActive = new NpgsqlCommand(sql, conn, tx);
        if (inactiveId.HasValue)
        {
            resetActive.Parameters.AddWithValue("inactive", inactiveId.Value);
        }
        resetActive.Parameters.AddWithValue("hash", passwordHash);
        await resetActive.ExecuteNonQueryAsync();
    }
}
