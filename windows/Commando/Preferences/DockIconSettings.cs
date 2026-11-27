namespace Commando.Preferences;

public static class DockIconSettings
{
    public static bool IsHidden => Storage.Preferences.HideDockIcon;

    public static void SetHidden(bool hidden)
    {
        Storage.Preferences.HideDockIcon = hidden;
        AppEvents.RaisePreferencesChanged();
    }
}
