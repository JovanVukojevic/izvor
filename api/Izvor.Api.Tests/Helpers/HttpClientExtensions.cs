using System.Net.Http.Headers;

namespace Izvor.Api.Tests.Helpers;

public static class HttpClientExtensions
{
    private const string BaseDomain = "izvor.lvh.me";

    public static HttpClient WithTenant(this HttpClient client, string subdomain)
    {
        // BaseAddress drives the URI's Host that TestServer reads — Host header
        // alone is not always honored by Kestrel's TestServer in all paths.
        // Setting BaseAddress is the canonical way to control the resolved host.
        client.BaseAddress = new Uri($"http://{subdomain}.{BaseDomain}");
        return client;
    }

    public static HttpClient WithBearer(this HttpClient client, string token)
    {
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }
}
