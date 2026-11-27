using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Commando.UI;

static class TrayIconPromotion
{
    const int HWND_BROADCAST = 0xffff;
    const int WM_SETTINGCHANGE = 0x001A;

    static int _running;

    public static void PromoteCurrentProcess()
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe))
        {
            return;
        }

        if (Interlocked.Exchange(ref _running, 1) == 1)
        {
            return;
        }

        _ = Task.Run(() =>
        {
            try
            {
                var deadline = DateTime.UtcNow.AddSeconds(8);
                var announced = false;
                while (DateTime.UtcNow < deadline)
                {
                    if (TryPromote(exe) && !announced)
                    {
                        announced = true;
                        NotifyExplorer();
                    }

                    Thread.Sleep(announced ? 400 : 200);
                }

                if (TryPromote(exe))
                {
                    NotifyExplorer();
                }
            }
            catch
            {
                // Promotion is best-effort. The icon still exists if Explorer has not created the key yet.
            }
            finally
            {
                Interlocked.Exchange(ref _running, 0);
            }
        });
    }

    static bool TryPromote(string exePath)
    {
        var target = ExpandPath(exePath);
        if (target == null)
        {
            return false;
        }

        using var root = Registry.CurrentUser.OpenSubKey(@"Control Panel\NotifyIconSettings", writable: true);
        if (root == null)
        {
            return false;
        }

        var found = false;
        foreach (var name in root.GetSubKeyNames())
        {
            using var sub = root.OpenSubKey(name, writable: true);
            if (sub == null)
            {
                continue;
            }

            var stored = ExpandPath(sub.GetValue("ExecutablePath"));
            if (stored == null || !string.Equals(stored, target, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            found = true;
            if (sub.GetValue("IsPromoted") is int promoted && promoted == 1)
            {
                continue;
            }

            sub.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
        }

        return found;
    }

    static string? ExpandPath(object? value)
    {
        if (value is not string text || string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        text = Environment.ExpandEnvironmentVariables(text.Trim().Trim('"'));
        if (text.Length > 3 && text[0] == '{')
        {
            var end = text.IndexOf('}');
            if (end > 1 && Guid.TryParse(text.AsSpan(1, end - 1), out var id))
            {
                var rest = text[(end + 1)..].TrimStart('\\', '/');
                var root = KnownFolder(id);
                if (!string.IsNullOrEmpty(root))
                {
                    text = string.IsNullOrEmpty(rest) ? root : Path.Combine(root, rest);
                }
            }
        }

        try
        {
            return Path.GetFullPath(text);
        }
        catch
        {
            return text;
        }
    }

    static string? KnownFolder(Guid id)
    {
        if (SHGetKnownFolderPath(id, 0, IntPtr.Zero, out var pointer) != 0 || pointer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return Marshal.PtrToStringUni(pointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(pointer);
        }
    }

    static void NotifyExplorer()
    {
        try
        {
            SendNotifyMessage(new IntPtr(HWND_BROADCAST), WM_SETTINGCHANGE, IntPtr.Zero, "TraySettings");
        }
        catch
        {
            // IsPromoted is the setting Explorer reads. The broadcast is only a refresh.
        }
    }

    [DllImport("shell32.dll")]
    static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr pszPath);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool SendNotifyMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
}
