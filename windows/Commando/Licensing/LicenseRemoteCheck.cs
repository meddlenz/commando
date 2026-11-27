using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace Commando.Licensing;

public static class LicenseRemoteCheck
{
    public sealed class RemoteResult
    {
        public RemoteResult(bool banned, bool ok)
        {
            Banned = banned;
            Ok = ok;
        }

        public bool Banned { get; }
        public bool Ok { get; }
    }

    static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromSeconds(8),
    };

    public static RemoteResult? ResponseOverride { get; set; }
    public static Uri? CheckUrlOverride { get; set; }
    public static Uri? ReportUrlOverride { get; set; }
    public static bool SkipNetwork { get; set; }

    public static RemoteResult? Refresh(string token, string version, string reason = "activation")
    {
        if (ResponseOverride != null)
        {
            return ResponseOverride;
        }

        if (SkipNetwork || LicenseStatus.StorageDirectoryOverride != null)
        {
            return null;
        }

        var trimmed = token.Trim();
        var url = RequestUrl(trimmed, version, reason);
        if (trimmed.Length == 0 || url == null)
        {
            return null;
        }

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            using var response = Http.Send(request);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var data = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
            return ParseResponse(data);
        }
        catch
        {
            return null;
        }
    }

    public static void ReportTamper(string token, string detail, string version)
    {
        if (SkipNetwork || LicenseStatus.StorageDirectoryOverride != null)
        {
            return;
        }

        var trimmed = token.Trim();
        if (trimmed.Length != 12)
        {
            return;
        }

        var url = ReportUrlOverride ?? AppInfo.LicenseReportUrl;
        var body = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["token"] = trimmed,
            ["reason"] = "integrity",
            ["version"] = version,
            ["detail"] = detail,
        });

        _ = Task.Run(async () =>
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, url);
                request.Content = new StringContent(body, Encoding.UTF8, "application/json");
                using var response = await Http.SendAsync(request).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    return;
                }

                var data = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                if (ParseReportBanned(data))
                {
                    void Apply() => LicenseStatus.ApplyAutoBanFromServer();
                    var dispatcher = System.Windows.Application.Current?.Dispatcher;
                    if (dispatcher != null)
                    {
                        dispatcher.Invoke(Apply);
                    }
                    else
                    {
                        Apply();
                    }
                }
            }
            catch
            {
                // Tamper reports are best-effort.
            }
        });
    }

    public static RemoteResult? ParseResponse(byte[] data)
    {
        try
        {
            using var document = JsonDocument.Parse(data);
            var root = document.RootElement;
            if (!root.TryGetProperty("banned", out var bannedElement)
                || (bannedElement.ValueKind != JsonValueKind.True && bannedElement.ValueKind != JsonValueKind.False))
            {
                return null;
            }

            var banned = bannedElement.GetBoolean();
            var ok = !banned;
            if (root.TryGetProperty("ok", out var okElement)
                && (okElement.ValueKind == JsonValueKind.True || okElement.ValueKind == JsonValueKind.False))
            {
                ok = okElement.GetBoolean();
            }

            return new RemoteResult(banned, ok);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static Uri? RequestUrl(string token, string version, string reason, Uri? baseUrl = null)
    {
        var url = CheckUrlOverride ?? baseUrl ?? AppInfo.LicenseCheckUrl;
        var builder = new UriBuilder(url);
        var query = new Dictionary<string, string>
        {
            ["token"] = token,
            ["version"] = version,
            ["reason"] = reason,
        };
        builder.Query = string.Join("&", query.Select(pair =>
            Uri.EscapeDataString(pair.Key) + "=" + Uri.EscapeDataString(pair.Value)));
        return builder.Uri;
    }

    static bool ParseReportBanned(byte[] data)
    {
        try
        {
            using var document = JsonDocument.Parse(data);
            return document.RootElement.TryGetProperty("banned", out var banned)
                && banned.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
