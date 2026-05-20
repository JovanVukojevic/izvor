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
}
