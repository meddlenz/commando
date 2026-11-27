using System.Globalization;
using Microsoft.Win32;

namespace Commando.Storage;

public static class AppStoragePaths
{
    public const string CommandSetsFileName = "command-sets.json";
    public const string RegistrationFileName = "registration.dat";

    public static string ApplicationSupportDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Commando");

    public static string LocalCommandSetsFile =>
        Path.Combine(ApplicationSupportDirectory, CommandSetsFileName);

    public static string RegistrationFile =>
        Path.Combine(ApplicationSupportDirectory, RegistrationFileName);

    public static string TerminalRunsDirectory =>
        Path.Combine(ApplicationSupportDirectory, "terminal-runs");

    public static string? OneDriveRoot => LocateOneDriveRoot();

    public static string? OneDriveCommandSetsFile
    {
        get
        {
            var root = OneDriveRoot;
            if (string.IsNullOrEmpty(root))
            {
                return null;
            }

            // Same shape as the Mac iCloud container: an app folder, then Documents, then the file.
            return Path.Combine(root, "Commando", "Documents", CommandSetsFileName);
        }
    }

    public static void EnsureDirectory(string directory)
    {
        Directory.CreateDirectory(directory);
    }

    static string? LocateOneDriveRoot()
    {
        try
        {
            var mounts = ReadSyncMounts(out var sawSyncStore);
            var candidates = ReadAccountCandidates(mounts, sawSyncStore);
            if (candidates.Count == 0)
            {
                return LegacyRootIfSyncing(mounts, sawSyncStore);
            }

            if (candidates.Count == 1)
            {
                return candidates[0].Folder;
            }

            var preferred = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\OneDrive", "UserFolder", null) as string;
            foreach (var candidate in candidates)
            {
                if (PathsEqual(candidate.Folder, preferred))
                {
                    return candidate.Folder;
                }
            }

            return candidates
                .OrderByDescending(candidate => candidate.Activity)
                .ThenByDescending(candidate => candidate.IsPersonal)
                .First()
                .Folder;
        }
        catch
        {
            return null;
        }
    }

    static string? LegacyRootIfSyncing(IReadOnlyList<SyncMount> mounts, bool sawSyncStore)
    {
        var root = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\OneDrive", "UserFolder", null) as string;
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
        {
            return null;
        }

        var mounted = mounts.Any(mount => PathsEqual(mount.Folder, root));
        if (mounted || !sawSyncStore)
        {
            return root;
        }

        return null;
    }

    static List<AccountChoice> ReadAccountCandidates(IReadOnlyList<SyncMount> mounts, bool sawSyncStore)
    {
        var choices = new List<AccountChoice>();
        using var accounts = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\OneDrive\Accounts");
        if (accounts == null)
        {
            return choices;
        }

        foreach (var name in accounts.GetSubKeyNames())
        {
            var personal = name.Equals("Personal", StringComparison.OrdinalIgnoreCase);
            var business = name.StartsWith("Business", StringComparison.OrdinalIgnoreCase);
            if (!personal && !business)
            {
                continue;
            }

            using var key = accounts.OpenSubKey(name);
            var folder = (key?.GetValue("UserFolder") as string)?.Trim();
            if (key == null || string.IsNullOrEmpty(folder) || !Directory.Exists(folder))
            {
                continue;
            }

            var signedIn = IsSignedIn(key);
            var cloudFiles = ReadFlag(key, "LastKnownCloudFilesEnabled");
            var mount = mounts.FirstOrDefault(item => PathsEqual(item.Folder, folder));
            var mounted = mount.Folder != null;
            var syncing = mounted || (signedIn && (cloudFiles == true || !sawSyncStore));
            if (!syncing || (!signedIn && !mounted))
            {
                continue;
            }

            choices.Add(new AccountChoice(folder, personal, mount.Activity));
        }

        return choices;
    }

    static bool IsSignedIn(RegistryKey key)
    {
        if (!string.IsNullOrWhiteSpace(key.GetValue("UserEmail") as string))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(key.GetValue("UserName") as string))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(key.GetValue("OneAuthAccountId") as string))
        {
            return true;
        }

        return key.GetValue("LastSignInTime") != null;
    }

    static bool? ReadFlag(RegistryKey key, string name)
    {
        var value = key.GetValue(name);
        if (value == null)
        {
            return null;
        }

        try
        {
            return Convert.ToInt32(value, CultureInfo.InvariantCulture) != 0;
        }
        catch
        {
            return null;
        }
    }

    static List<SyncMount> ReadSyncMounts(out bool sawSyncStore)
    {
        var mounts = new List<SyncMount>();
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\SyncEngines\Providers\OneDrive");
        sawSyncStore = key != null;
        if (key == null)
        {
            return mounts;
        }

        foreach (var name in key.GetSubKeyNames())
        {
            using var sub = key.OpenSubKey(name);
            var folder = (sub?.GetValue("MountPoint") as string)?.Trim();
            if (string.IsNullOrEmpty(folder))
            {
                continue;
            }

            DateTime activity = DateTime.MinValue;
            if (sub?.GetValue("LastModifiedTime") is string stamp
                && DateTime.TryParse(stamp, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var parsed))
            {
                activity = parsed;
            }

            mounts.Add(new SyncMount(folder, activity));
        }

        return mounts;
    }

    static bool PathsEqual(string? left, string? right)
    {
        var a = Canonical(left);
        var b = Canonical(right);
        return a != null && b != null && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }

    static string? Canonical(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path.Trim().Trim('"')));
        }
        catch
        {
            return path.Trim().Trim('"');
        }
    }

    readonly struct SyncMount
    {
        public SyncMount(string folder, DateTime activity)
        {
            Folder = folder;
            Activity = activity;
        }

        public string Folder { get; }
        public DateTime Activity { get; }
    }

    readonly struct AccountChoice
    {
        public AccountChoice(string folder, bool isPersonal, DateTime activity)
        {
            Folder = folder;
            IsPersonal = isPersonal;
            Activity = activity;
        }

        public string Folder { get; }
        public bool IsPersonal { get; }
        public DateTime Activity { get; }
    }
}
