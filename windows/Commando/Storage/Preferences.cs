using System.Text.Json;

namespace Commando.Storage;

public static class Preferences
{
    const string ExampleRemovedKey = "exampleCommandSetRemoved";
    const string ICloudSyncKey = "syncCommandSetsViaiCloud";
    const string TerminalPathKey = "terminalAppPath";
    const string MenuBarIconKey = "menuBarIcon";
    const string HideDockIconKey = "hideDockIcon";
    const string LaunchAtLoginKey = "launchAtLogin";

    static readonly object Gate = new();
    static Dictionary<string, JsonElement>? _values;

    public static string? FileOverride { get; set; }

    public static string FilePath =>
        FileOverride ?? Path.Combine(AppStoragePaths.ApplicationSupportDirectory, "preferences.json");

    public static bool ExampleCommandSetRemoved
    {
        get => GetBool(ExampleRemovedKey);
        set => SetBool(ExampleRemovedKey, value);
    }

    public static bool ICloudSyncEnabled
    {
        get => GetBool(ICloudSyncKey);
        set => SetBool(ICloudSyncKey, value);
    }

    public static string? TerminalAppPath
    {
        get => GetString(TerminalPathKey);
        set => SetString(TerminalPathKey, value);
    }

    public static string? LegacyTerminalApplication => GetString("terminalApplication");

    public static string? MenuBarIcon
    {
        get => GetString(MenuBarIconKey);
        set => SetString(MenuBarIconKey, value);
    }

    public static bool HideDockIcon
    {
        get => GetBool(HideDockIconKey);
        set => SetBool(HideDockIconKey, value);
    }

    public static bool LaunchAtLoginFlag
    {
        get => GetBool(LaunchAtLoginKey);
        set => SetBool(LaunchAtLoginKey, value);
    }

    public static void ResetCache()
    {
        lock (Gate)
        {
            _values = null;
        }
    }

    static bool GetBool(string key)
    {
        lock (Gate)
        {
            if (!EnsureLoaded() || !_values!.TryGetValue(key, out var value))
            {
                return false;
            }

            return value.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.String => bool.TryParse(value.GetString(), out var parsed) && parsed,
                _ => false,
            };
        }
    }

    static void SetBool(string key, bool value)
    {
        lock (Gate)
        {
            EnsureLoaded();
            _values![key] = JsonSerializer.SerializeToElement(value);
            Save();
        }
    }

    static string? GetString(string key)
    {
        lock (Gate)
        {
            if (!EnsureLoaded() || !_values!.TryGetValue(key, out var value) || value.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            var text = value.GetString();
            return string.IsNullOrEmpty(text) ? null : text;
        }
    }

    static void SetString(string key, string? value)
    {
        lock (Gate)
        {
            EnsureLoaded();
            if (string.IsNullOrEmpty(value))
            {
                _values!.Remove(key);
            }
            else
            {
                _values![key] = JsonSerializer.SerializeToElement(value);
            }

            Save();
        }
    }

    static bool EnsureLoaded()
    {
        if (_values != null)
        {
            return true;
        }

        _values = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        try
        {
            if (!File.Exists(FilePath))
            {
                return true;
            }

            var json = File.ReadAllText(FilePath);
            var loaded = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json);
            if (loaded != null)
            {
                _values = loaded;
            }
        }
        catch
        {
            _values = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        }

        return true;
    }

    static void Save()
    {
        var path = FilePath;
        AppStoragePaths.EnsureDirectory(Path.GetDirectoryName(path)!);
        var json = JsonSerializer.Serialize(_values, new JsonSerializerOptions { WriteIndented = true });
        var temp = path + ".tmp";
        File.WriteAllText(temp, json);
        File.Move(temp, path, overwrite: true);
    }
}
