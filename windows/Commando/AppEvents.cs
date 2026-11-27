namespace Commando;

public static class AppEvents
{
    public static event Action? CommandSetsChanged;
    public static event Action? PreferencesChanged;
    public static event Action? LicenseChanged;

    public static void RaiseCommandSetsChanged() => CommandSetsChanged?.Invoke();

    public static void RaisePreferencesChanged() => PreferencesChanged?.Invoke();

    public static void RaiseLicenseChanged() => LicenseChanged?.Invoke();
}
