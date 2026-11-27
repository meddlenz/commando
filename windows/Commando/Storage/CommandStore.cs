using System.IO;
using Commando.Models;

namespace Commando.Storage;

public static class CommandStore
{
    public enum ImportMode
    {
        Merge,
        Replace,
    }

    public sealed class StoreException : Exception
    {
        public StoreException(string message) : base(message)
        {
        }

        public static StoreException OneDriveUnavailable { get; } = new(
            "OneDrive is not available. Sign in to OneDrive and try again.");
    }

    static readonly object Gate = new();
    static List<CommandSet>? _cache;
    static bool _started;
    static int _writeDepth;
    static FileSystemWatcher? _watcher;
    static SynchronizationContext? _ui;

    public static string? StorageDirectoryOverride { get; set; }

    public static bool IsCloudSyncEnabled =>
        StorageDirectoryOverride == null && Preferences.OneDriveSyncEnabled;

    public static List<CommandSet> CommandSets
    {
        get
        {
            lock (Gate)
            {
                _cache ??= LoadFromActiveFile() ?? MigrateLegacyIfNeeded();
                return _cache.Select(set => set.Clone()).ToList();
            }
        }
        set
        {
            List<CommandSet> copy;
            lock (Gate)
            {
                copy = value.Select(set => set.Clone()).ToList();
                _cache = copy.Select(set => set.Clone()).ToList();
                try
                {
                    Write(copy, ActiveFilePath());
                }
                catch
                {
                    return;
                }
            }

            AppEvents.RaiseCommandSetsChanged();
        }
    }

    public static void Start()
    {
        lock (Gate)
        {
            if (_started)
            {
                return;
            }

            _started = true;
            _ui = SynchronizationContext.Current;
        }

        _ = CommandSets;
        WatchActiveFile();
    }

    public static void SetCloudSyncEnabled(bool enabled)
    {
        if (StorageDirectoryOverride != null)
        {
            return;
        }

        if (enabled)
        {
            var cloudPath = ActiveOneDriveFilePath();
            var localSets = Load(LocalFilePath()) ?? CommandSets;
            var cloudSets = Load(cloudPath) ?? new List<CommandSet>();
            List<CommandSet> merged;
            if (cloudSets.Count == 0)
            {
                merged = localSets;
            }
            else if (localSets.Count == 0)
            {
                merged = cloudSets;
            }
            else
            {
                merged = CommandSetDocument.Merge(cloudSets, localSets);
            }

            Write(merged, cloudPath);
            Preferences.OneDriveSyncEnabled = true;
            lock (Gate)
            {
                _cache = merged.Select(set => set.Clone()).ToList();
            }
        }
        else
        {
            var current = CommandSets;
            Write(current, LocalFilePath());
            Preferences.OneDriveSyncEnabled = false;
            lock (Gate)
            {
                _cache = current.Select(set => set.Clone()).ToList();
            }
        }

        WatchActiveFile();
        AppEvents.RaiseCommandSetsChanged();
    }

    public static void ImportDocument(string path, ImportMode mode)
    {
        var imported = CommandSetDocument.Decode(File.ReadAllBytes(path)).ToList();
        var next = mode switch
        {
            ImportMode.Replace => imported,
            _ => CommandSetDocument.Merge(CommandSets, imported),
        };

        Licensing.LicenseStatus.EnsureCanImport(next.Count);
        CommandSets = next;
    }

    public static void ExportDocument(string path)
    {
        Write(CommandSets, path);
    }

    public static void ResetCache()
    {
        lock (Gate)
        {
            _cache = null;
        }
    }

    static void WatchActiveFile()
    {
        try
        {
            var path = ActiveFilePath();
            var directory = Path.GetDirectoryName(path);
            if (string.IsNullOrEmpty(directory))
            {
                return;
            }

            AppStoragePaths.EnsureDirectory(directory);
            _watcher?.Dispose();
            _watcher = new FileSystemWatcher(directory, Path.GetFileName(path))
            {
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                EnableRaisingEvents = true,
            };
            _watcher.Changed += (_, _) => HandleExternalChange();
            _watcher.Created += (_, _) => HandleExternalChange();
            _watcher.Renamed += (_, _) => HandleExternalChange();
        }
        catch
        {
            // Watching is best-effort. The file is still read on each launch.
        }
    }

    static void HandleExternalChange()
    {
        if (Volatile.Read(ref _writeDepth) > 0)
        {
            return;
        }

        List<CommandSet> loaded;
        try
        {
            loaded = LoadFromActiveFile() ?? new List<CommandSet>();
        }
        catch
        {
            return;
        }

        void Apply()
        {
            lock (Gate)
            {
                var current = _cache ?? new List<CommandSet>();
                if (CommandSetDocument.EncodeString(current) == CommandSetDocument.EncodeString(loaded))
                {
                    return;
                }

                _cache = loaded.Select(set => set.Clone()).ToList();
            }

            AppEvents.RaiseCommandSetsChanged();
        }

        if (_ui != null)
        {
            _ui.Post(_ => Apply(), null);
        }
        else
        {
            Apply();
        }
    }

    static List<CommandSet>? LoadFromActiveFile()
    {
        string path;
        try
        {
            path = ActiveFilePath();
        }
        catch
        {
            return null;
        }

        if (File.Exists(path))
        {
            return Load(path) ?? new List<CommandSet>();
        }

        return null;
    }

    static List<CommandSet>? Load(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }

            return CommandSetDocument.Decode(File.ReadAllBytes(path)).ToList();
        }
        catch
        {
            return null;
        }
    }

    static void Write(IReadOnlyList<CommandSet> commandSets, string path)
    {
        var data = CommandSetDocument.Encode(commandSets);
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
        {
            AppStoragePaths.EnsureDirectory(directory);
        }

        var temp = path + ".tmp";
        Interlocked.Increment(ref _writeDepth);
        try
        {
            File.WriteAllBytes(temp, data);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            Interlocked.Decrement(ref _writeDepth);
        }
    }

    static string ActiveFilePath()
    {
        if (IsCloudSyncEnabled && AppStoragePaths.OneDriveCommandSetsFile is { } cloud)
        {
            return cloud;
        }

        return LocalFilePath();
    }

    static string ActiveOneDriveFilePath()
    {
        return AppStoragePaths.OneDriveCommandSetsFile ?? throw StoreException.OneDriveUnavailable;
    }

    static string LocalFilePath()
    {
        if (StorageDirectoryOverride != null)
        {
            return Path.Combine(StorageDirectoryOverride, AppStoragePaths.CommandSetsFileName);
        }

        return AppStoragePaths.LocalCommandSetsFile;
    }

    static List<CommandSet> MigrateLegacyIfNeeded()
    {
        if (StorageDirectoryOverride != null)
        {
            return new List<CommandSet>();
        }

        var migrated = new List<CommandSet>();
        try
        {
            Write(migrated, ActiveFilePath());
        }
        catch
        {
            // A later save will create the file.
        }

        return migrated;
    }
}
