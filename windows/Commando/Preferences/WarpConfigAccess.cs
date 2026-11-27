namespace Commando.Preferences;

public static class WarpConfigAccess
{
    public static string ConfigDirectoryName(string appPath)
    {
        var file = Path.GetFileName(appPath).ToLowerInvariant();
        var display = TerminalAppSettings.DisplayName(appPath).ToLowerInvariant();
        var combined = file + " " + display + " " + appPath.ToLowerInvariant();
        if (combined.Contains("preview"))
        {
            return ".warp-preview";
        }

        return ".warp";
    }

    public static string DefaultConfigDirectory(string appPath) =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ConfigDirectoryName(appPath));

    public static bool IsExpectedConfigDirectory(string path, string appPath)
    {
        var selected = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var expected = Path.GetFullPath(DefaultConfigDirectory(appPath)).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return string.Equals(selected, expected, StringComparison.OrdinalIgnoreCase);
    }

    public static string UrlScheme(string appPath)
    {
        var combined = (Path.GetFileName(appPath) + " " + TerminalAppSettings.DisplayName(appPath)).ToLowerInvariant();
        return combined.Contains("preview") ? "warppreview" : "warp";
    }
}
