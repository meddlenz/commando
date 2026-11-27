using System.Xml.Linq;

namespace Commando.Updates;

public sealed class UpdateInfo
{
    public string? CurrentMacOs { get; init; }
    public string? CurrentMacOsChangeLog { get; init; }
    public Uri? MacOsUrl { get; init; }
    public string? CurrentWindows { get; init; }
    public string? CurrentWindowsChangeLog { get; init; }
    public Uri? WindowsUrl { get; init; }
    public string? MinimumVersionAllowed { get; init; }
}

public static class UpdateInfoParser
{
    public static UpdateInfo? Parse(byte[] data)
    {
        try
        {
            var document = XDocument.Parse(System.Text.Encoding.UTF8.GetString(data));
            return new UpdateInfo
            {
                CurrentMacOs = Text(document, "currentMacOS"),
                CurrentMacOsChangeLog = Text(document, "currentMacOSChangeLog"),
                MacOsUrl = Url(document, "macOSUrl"),
                CurrentWindows = Text(document, "currentWindows"),
                CurrentWindowsChangeLog = Text(document, "currentWindowsChangeLog"),
                WindowsUrl = Url(document, "windowsUrl"),
                MinimumVersionAllowed = Text(document, "minimumVersionAllowed"),
            };
        }
        catch
        {
            return null;
        }
    }

    static string? Text(XDocument document, string name)
    {
        var value = document.Descendants(name).FirstOrDefault()?.Value;
        if (value == null)
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length == 0 ? null : trimmed;
    }

    static Uri? Url(XDocument document, string name)
    {
        var text = Text(document, name);
        return text != null && Uri.TryCreate(text, UriKind.Absolute, out var uri) ? uri : null;
    }
}

public static class UpdateChecker
{
    static readonly Uri UpdateInfoUrl = new("https://manticore.nz/commando/commando.xml");
    static readonly HashSet<string> AllowedUpdateHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "files.mac-attic.com",
        "manticore.nz",
    };

    static string? _dismissedVersionThisSession;

    public static void CheckForUpdateIfNeeded()
    {
        _ = Task.Run(async () =>
        {
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                using var response = await client.GetAsync(UpdateInfoUrl).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    return;
                }

                var data = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                var info = UpdateInfoParser.Parse(data);
                if (info == null)
                {
                    return;
                }

                void Apply()
                {
                    EnforceMinimumVersionIfNeeded(info);
                    if (Licensing.AppLock.IsLocked)
                    {
                        return;
                    }

                    var remoteVersion = info.CurrentWindows;
                    var changeLog = info.CurrentWindowsChangeLog;
                    if (string.IsNullOrEmpty(remoteVersion) || string.IsNullOrEmpty(changeLog))
                    {
                        return;
                    }

                    if (!IsVersion(remoteVersion, greaterThan: LocalVersion()))
                    {
                        return;
                    }

                    var message = DecodeChangeLog(changeLog);
                    if (message.Length == 0 || _dismissedVersionThisSession == remoteVersion)
                    {
                        return;
                    }

                    ShowUpdateAvailable(message, remoteVersion, info);
                }

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
            catch
            {
                // Update checks are best-effort.
            }
        });
    }

    public static void EnforceMinimumVersionIfNeeded(UpdateInfo updateInfo)
    {
        var minimum = updateInfo.MinimumVersionAllowed;
        if (string.IsNullOrEmpty(minimum) || !IsVersion(minimum, greaterThan: LocalVersion()))
        {
            return;
        }

        Licensing.AppLock.LockForUpdate(minimum, UpdateUrl(updateInfo.WindowsUrl ?? updateInfo.MacOsUrl));
        if (System.Windows.Application.Current == null)
        {
            return;
        }

        var versionLabel = updateInfo.CurrentWindows ?? updateInfo.CurrentMacOs ?? minimum;
        var notes = DecodeChangeLog(updateInfo.CurrentWindowsChangeLog ?? updateInfo.CurrentMacOsChangeLog ?? "");
        var message = notes.Length == 0
            ? Licensing.AppLock.UpdateRequiredMessage
            : Licensing.AppLock.UpdateRequiredMessage + "\n\n" + notes;
        Commando.UI.UpdateWindow.Present(versionLabel, message, UpdateUrl(updateInfo.WindowsUrl), required: true, () => { });
    }

    public static string LocalVersion() => AppInfo.ShortVersion;

    public static bool IsVersion(string remote, string greaterThan)
    {
        var remoteParts = remote.Split('.').Select(part => int.TryParse(part, out var value) ? value : 0).ToArray();
        var localParts = greaterThan.Split('.').Select(part => int.TryParse(part, out var value) ? value : 0).ToArray();
        var count = Math.Max(remoteParts.Length, localParts.Length);
        for (var index = 0; index < count; index++)
        {
            var remoteValue = index < remoteParts.Length ? remoteParts[index] : 0;
            var localValue = index < localParts.Length ? localParts[index] : 0;
            if (remoteValue > localValue)
            {
                return true;
            }

            if (remoteValue < localValue)
            {
                return false;
            }
        }

        return false;
    }

    public static Uri? UpdateUrl(Uri? url)
    {
        var normalized = NormalizedUpdateUrl(url);
        return normalized != null && IsAllowedUpdateUrl(normalized) ? normalized : null;
    }

    public static bool IsAllowedUpdateUrl(Uri? url)
    {
        var normalized = NormalizedUpdateUrl(url);
        if (normalized == null)
        {
            return false;
        }

        var scheme = normalized.Scheme.ToLowerInvariant();
        var host = normalized.Host.ToLowerInvariant();
        return scheme == "https" && AllowedUpdateHosts.Contains(host);
    }

    public static string UpdateActionTitle() => "Download";

    static Uri? NormalizedUpdateUrl(Uri? url)
    {
        if (url == null || string.IsNullOrEmpty(url.Host) || !AllowedUpdateHosts.Contains(url.Host))
        {
            return null;
        }

        if (url.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase))
        {
            var builder = new UriBuilder(url) { Scheme = "https", Port = -1 };
            return builder.Uri;
        }

        return url;
    }

    static string DecodeChangeLog(string text) =>
        text.Replace("&lt;br&gt;", "\n", StringComparison.OrdinalIgnoreCase)
            .Replace("<br/>", "\n", StringComparison.OrdinalIgnoreCase)
            .Replace("<br />", "\n", StringComparison.OrdinalIgnoreCase)
            .Replace("<br>", "\n", StringComparison.OrdinalIgnoreCase)
            .Replace("&amp;", "&")
            .Replace("&quot;", "\"")
            .Replace("&#39;", "'")
            .Replace("&nbsp;", " ")
            .Trim();

    static void ShowUpdateAvailable(string message, string remoteVersion, UpdateInfo updateInfo)
    {
        Commando.UI.UpdateWindow.Present(
            remoteVersion,
            message,
            UpdateUrl(updateInfo.WindowsUrl),
            required: false,
            () => _dismissedVersionThisSession = remoteVersion);
    }
}
