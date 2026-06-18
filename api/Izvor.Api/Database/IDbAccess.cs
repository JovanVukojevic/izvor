namespace Izvor.Api.Database;

public interface IDbAccess
{
    Task<T?> CallAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<T>> QueryAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);

    Task ExecuteAsync(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);

    Task<T> InTransactionAsync<T>(
        Func<IDbTransactionScope, Task<T>> work,
        CancellationToken cancellationToken = default);

    Task InTransactionAsync(
        Func<IDbTransactionScope, Task> work,
        CancellationToken cancellationToken = default);
}

public interface IDbTransactionScope
{
    Task SetTenantAsync(Guid tenantId, CancellationToken cancellationToken = default);

    Task SetUserAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<T?> CallAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<T>> QueryAsync<T>(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);

    Task ExecuteAsync(
        string functionName,
        object? parameters = null,
        CancellationToken cancellationToken = default);
}
