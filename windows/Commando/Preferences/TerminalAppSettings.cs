using System.Diagnostics;

namespace Commando.Preferences;

public static class TerminalAppSettings
{
    public static readonly string[] SupportedTerminalNames = { "Windows Terminal", "Warp", "Ghostty" };

    const string PathKey = "terminalAppPath";

    public static string DefaultPath
    {
        get
        {
            var windowsTerminal = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Microsoft",
                "WindowsApps",
                "wt.exe");
            if (File.Exists(windowsTerminal))
            {
                return windowsTerminal;
            }

            var powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (File.Exists(powershell))
            {
                return powershell;
            }

            return Path.Combine(Environment.SystemDirectory, "cmd.exe");
        }
    }

    public static string SelectedAppPath
    {
        get
        {
            var path = Storage.Preferences.TerminalAppPath;
            if (!string.IsNullOrEmpty(path) && File.Exists(path))
            {
                return path;
            }

            return DefaultPath;
        }
        set
        {
            Storage.Preferences.TerminalAppPath = value;
            AppEvents.RaisePreferencesChanged();
        }
    }

    public static string SelectedAppName => DisplayName(SelectedAppPath);

    public static string DisplayName(string appPath)
    {
        var file = Path.GetFileName(appPath);
        if (file.Equals("wt.exe", StringComparison.OrdinalIgnoreCase))
        {
            return "Windows Terminal";
        }

        try
        {
            var description = FileVersionInfo.GetVersionInfo(appPath).FileDescription;
            if (!string.IsNullOrWhiteSpace(description))
            {
                return description;
            }
        }
        catch
        {
            // Some execution aliases do not expose a version resource.
        }

        var name = Path.GetFileNameWithoutExtension(appPath);
        return string.IsNullOrEmpty(name) ? appPath : name;
    }

    public static bool IsOfficiallySupported(string appPath) => OfficialName(appPath) != null;

    public static string? OfficialName(string appPath)
    {
        var file = Path.GetFileName(appPath).ToLowerInvariant();
        var display = DisplayName(appPath).ToLowerInvariant();
        var combined = string.Join(" ", file, display, appPath.ToLowerInvariant());
        if (file == "wt.exe" || display == "windows terminal" || combined.Contains("windowsterminal"))
        {
            return "Windows Terminal";
        }

        if (combined.Contains("warp"))
        {
            return "Warp";
        }

        if (combined.Contains("ghostty"))
        {
            return "Ghostty";
        }

        return null;
    }
}
