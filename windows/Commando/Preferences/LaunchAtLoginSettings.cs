using Microsoft.Win32;

namespace Commando.Preferences;

public static class LaunchAtLoginSettings
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ValueName = "Commando";

    public sealed class LaunchAtLoginException : Exception
    {
        public LaunchAtLoginException() : base("Could not add Commando to login items.")
        {
        }
    }

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
                return key?.GetValue(ValueName) is string;
            }
            catch
            {
                return Storage.Preferences.LaunchAtLoginFlag;
            }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                ?? Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (key == null)
            {
                throw new LaunchAtLoginException();
            }

            if (enabled)
            {
                var exe = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exe))
                {
                    throw new LaunchAtLoginException();
                }

                key.SetValue(ValueName, "\"" + exe + "\"");
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
        catch (LaunchAtLoginException)
        {
            throw;
        }
        catch
        {
            throw new LaunchAtLoginException();
        }

        Storage.Preferences.LaunchAtLoginFlag = enabled;
        AppEvents.RaisePreferencesChanged();
    }
}
