using Npgsql;
using Testcontainers.PostgreSql;
using Xunit;

namespace Izvor.Api.Tests.Fixtures;

public sealed class PostgresFixture : IAsyncLifetime
{
    private const string DatabaseName = "izvor";
    private const string SuperuserPassword = "postgres";

    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16")
        .WithDatabase(DatabaseName)
        .WithUsername("postgres")
        .WithPassword(SuperuserPassword)
        .Build();

    public string AppConnectionString { get; private set; } = string.Empty;
    public string AdminConnectionString { get; private set; } = string.Empty;

    public async Task InitializeAsync()
    {
        var dbDir = ResolveDbDirectory();

        await _container.StartAsync();

        var superConnString = _container.GetConnectionString();
        await ExecuteSqlFileAsync(superConnString, Path.Combine(dbDir, "init.sql"));

        var adminConnString = BuildConnectionString(superConnString, "izvor_admin", "izvor_admin_dev");
        var migrationsDir = Path.Combine(dbDir, "migrations");
        var migrationFiles = Directory.GetFiles(migrationsDir, "*.sql")
            .OrderBy(f => f, StringComparer.Ordinal)
            .ToArray();
        foreach (var file in migrationFiles)
        {
            await ExecuteSqlFileAsync(adminConnString, file);
        }

        // Seed runs as the postgres superuser, which bypasses RLS automatically.
        // izvor_admin is subject to FORCE RLS (no BYPASSRLS attribute) and would
        // need per-tenant set_config calls between inserts — superuser is simpler.
        await TestSeed.SeedAsync(superConnString);

        AdminConnectionString = adminConnString;
        AppConnectionString = BuildConnectionString(superConnString, "izvor_app", "izvor_app_dev");
    }

    public async Task DisposeAsync() => await _container.DisposeAsync();

    private static string ResolveDbDirectory()
    {
        var envOverride = Environment.GetEnvironmentVariable("IZVOR_REPO_ROOT");
        var repoRoot = !string.IsNullOrWhiteSpace(envOverride)
            ? envOverride
            : Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

        var dbDir = Path.Combine(repoRoot, "db");
        var initSql = Path.Combine(dbDir, "init.sql");

        if (!File.Exists(initSql))
        {
            throw new InvalidOperationException(
                $"PostgresFixture could not locate db/init.sql.{Environment.NewLine}" +
                $"Resolved path: {dbDir}.{Environment.NewLine}" +
                "If running tests from a non-standard layout, set IZVOR_REPO_ROOT environment variable to the repo root.");
        }

        return dbDir;
    }

    private static string BuildConnectionString(string baseConnString, string username, string password)
    {
        var builder = new NpgsqlConnectionStringBuilder(baseConnString)
        {
            Username = username,
            Password = password,
            IncludeErrorDetail = true
        };
        return builder.ConnectionString;
    }

    private static async Task ExecuteSqlFileAsync(string connectionString, string sqlFilePath)
    {
        var sql = await File.ReadAllTextAsync(sqlFilePath);
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync();
    }
}
