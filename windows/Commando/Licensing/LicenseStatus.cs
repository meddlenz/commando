using System.Text.Json;
using Commando.Models;
using Commando.Storage;

namespace Commando.Licensing;

public enum RegistrationErrorKind
{
    Revoked,
    RegistrationRequired,
    MissingFields,
    InvalidKey,
    UpdateRequired,
}

public sealed class RegistrationException : Exception
{
    public RegistrationException(RegistrationErrorKind kind) : base(MessageFor(kind))
    {
        Kind = kind;
    }

    public RegistrationErrorKind Kind { get; }

    public static string MessageFor(RegistrationErrorKind kind) => kind switch
    {
        RegistrationErrorKind.MissingFields => "Enter your full name, email, and license key.",
        RegistrationErrorKind.InvalidKey => "That license key does not match this name and email.",
        RegistrationErrorKind.RegistrationRequired => "Please purchase Commando to unlock its full capabilities.",
        RegistrationErrorKind.Revoked => "This license has been revoked. Please get in touch with Manticore SW for more information.",
        _ => AppLock.UpdateRequiredMessage,
    };
}

public static class LicenseStatus
{
    static readonly object Gate = new();
    static readonly TimeSpan RemoteRefreshInterval = TimeSpan.FromHours(24);
    static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = null,
        WriteIndented = false,
    };

    static bool? _cachedRevoked;
    static DateTime? _lastSuccessfulRemoteCheck;
    static ulong _remoteCheckId;
    static System.Threading.Timer? _periodicTimer;

    public static bool? IsRevokedOverride { get; set; }
    public static string? StorageDirectoryOverride { get; set; }

    public static string RegistrationFilePath =>
        StorageDirectoryOverride != null
            ? Path.Combine(StorageDirectoryOverride, AppStoragePaths.RegistrationFileName)
            : AppStoragePaths.RegistrationFile;

    public static bool IsUnlocked => IsUnlockedPublicState;

    public static bool IsUnlockedPublicState
    {
        get
        {
            if (AppLock.IsLocked || IsRevoked)
            {
                return false;
            }

            return HasValidStoredKey;
        }
    }

    public static bool IsRevoked
    {
        get
        {
            if (IsRevokedOverride != null)
            {
                return IsRevokedOverride.Value;
            }

            lock (Gate)
            {
                return _cachedRevoked == true;
            }
        }
    }

    public static string? StoredLicenseId => ReadRecord()?.LicenseId;

    public static string? RegisteredLine
    {
        get
        {
            if (IsRevoked || AppLock.IsLocked)
            {
                return null;
            }

            var name = StoredName;
            if (HasValidStoredKey && !string.IsNullOrEmpty(name))
            {
                return "Registered to: " + name;
            }

            return null;
        }
    }

    public static string? StoredName => ReadRecord()?.Name;

    public static bool HasValidStoredLicense()
    {
        var record = ReadRecord();
        return record != null && LicenseKey.IsValid(record.Name, record.Email, record.Key);
    }

    public static void Register(string name, string email, string key)
    {
        EnsureNotAppLocked();
        var trimmedName = LicenseKey.CanonicalName(name);
        var trimmedEmail = LicenseKey.CanonicalEmail(email);
        var trimmedKey = key.Trim();
        if (trimmedName.Length == 0 || trimmedEmail.Length == 0 || trimmedKey.Length == 0)
        {
            throw new RegistrationException(RegistrationErrorKind.MissingFields);
        }

        if (!LicenseKey.IsValid(trimmedName, trimmedEmail, trimmedKey))
        {
            throw new RegistrationException(RegistrationErrorKind.InvalidKey);
        }

        var licenseId = LicenseKey.LicenseId(trimmedKey) ?? LicenseKey.BanToken(trimmedKey);
        lock (Gate)
        {
            if (_cachedRevoked == true)
            {
                throw new RegistrationException(RegistrationErrorKind.Revoked);
            }
        }

        var remote = LicenseRemoteCheck.Refresh(licenseId, AppInfo.ShortVersion, "register");
        if (remote is { Banned: true })
        {
            lock (Gate)
            {
                _cachedRevoked = true;
            }

            throw new RegistrationException(RegistrationErrorKind.Revoked);
        }

        Write(new Record
        {
            Name = trimmedName,
            Email = trimmedEmail,
            Key = trimmedKey,
            LicenseId = licenseId,
            CachedRevoked = false,
            LastSuccessfulRemoteCheck = remote == null ? null : DateTime.UtcNow,
        });

        lock (Gate)
        {
            _cachedRevoked = false;
            _lastSuccessfulRemoteCheck = remote == null ? null : DateTime.UtcNow;
            _remoteCheckId++;
        }

        LicenseGuard.RefreshSentinel(true);
        AppEvents.RaiseLicenseChanged();
    }

    public static void Clear()
    {
        lock (Gate)
        {
            _remoteCheckId++;
            _cachedRevoked = null;
            _lastSuccessfulRemoteCheck = null;
        }

        if (File.Exists(RegistrationFilePath))
        {
            File.Delete(RegistrationFilePath);
        }

        LicenseGuard.RefreshSentinel(false);
        AppEvents.RaiseLicenseChanged();
    }

    public static void HydrateFromStorage()
    {
        _ = ReadRecord();
        if (HasValidStoredKey)
        {
            LicenseGuard.RefreshSentinel(!IsRevoked);
        }
    }

    public static void ResetSessionState()
    {
        lock (Gate)
        {
            _remoteCheckId++;
            _cachedRevoked = null;
            _lastSuccessfulRemoteCheck = null;
            IsRevokedOverride = null;
        }
    }

    public static void StartPeriodicRemoteRefreshIfNeeded()
    {
        RefreshRemoteStatusIfStale();
        _periodicTimer?.Dispose();
        _periodicTimer = new System.Threading.Timer(_ => RefreshRemoteStatus(), null, RemoteRefreshInterval, RemoteRefreshInterval);
    }

    public static void RefreshRemoteStatusIfStale()
    {
        if (ReadRecord() == null)
        {
            return;
        }

        lock (Gate)
        {
            if (_lastSuccessfulRemoteCheck != null
                && DateTime.UtcNow - _lastSuccessfulRemoteCheck.Value < RemoteRefreshInterval)
            {
                return;
            }
        }

        RefreshRemoteStatus();
    }

    public static void RefreshRemoteStatus()
    {
        var record = ReadRecord();
        if (record == null || !LicenseKey.IsValid(record.Name, record.Email, record.Key))
        {
            lock (Gate)
            {
                _cachedRevoked = null;
            }

            return;
        }

        ulong checkId;
        lock (Gate)
        {
            checkId = _remoteCheckId;
        }

        var token = record.LicenseId;
        Task.Run(() =>
        {
            var remote = LicenseRemoteCheck.Refresh(token, AppInfo.ShortVersion, "activation");
            void Apply()
            {
                lock (Gate)
                {
                    if (checkId != _remoteCheckId)
                    {
                        return;
                    }
                }

                if (!HasValidStoredKey)
                {
                    lock (Gate)
                    {
                        _cachedRevoked = null;
                    }

                    return;
                }

                ApplyRemoteResult(remote, record);
                AppEvents.RaiseLicenseChanged();
            }

            var dispatcher = System.Windows.Application.Current?.Dispatcher;
            if (dispatcher != null && !dispatcher.CheckAccess())
            {
                dispatcher.Invoke(Apply);
            }
            else
            {
                Apply();
            }
        });
    }

    public static void RunStartupIntegrityCheck()
    {
        var issue = LicenseGuard.RunIntegrityChecks();
        if (issue != null)
        {
            LicenseGuard.ReportIntegrityIssue(issue.Value);
        }
    }

    public static void EnsureCanAddCommandSet(int existingCount)
    {
        EnsureNotAppLocked();
        EnsureIntegrityAllowsAccess();
        if (LicenseGuard.Permits(LicenseGuard.Feature.AddCommandSet) || existingCount < 1)
        {
            return;
        }

        throw Restriction();
    }

    public static void EnsureCanAddSession()
    {
        EnsureNotAppLocked();
        EnsureIntegrityAllowsAccess();
        if (LicenseGuard.Permits(LicenseGuard.Feature.AddSession))
        {
            return;
        }

        throw Restriction();
    }

    public static void EnsureCanSaveSessions(int count)
    {
        EnsureNotAppLocked();
        EnsureIntegrityAllowsAccess();
        if (LicenseGuard.Permits(LicenseGuard.Feature.AddSession) || count <= 1)
        {
            return;
        }

        throw Restriction();
    }

    public static void EnsureCanImport(int resultingCount)
    {
        EnsureNotAppLocked();
        EnsureIntegrityAllowsAccess();
        if (LicenseGuard.Permits(LicenseGuard.Feature.ImportSets) || resultingCount <= 1)
        {
            return;
        }

        throw Restriction();
    }

    public static void EnsureCanRun(CommandSet commandSet)
    {
        EnsureNotAppLocked();
        EnsureIntegrityAllowsAccess();
        if (LicenseGuard.Permits(LicenseGuard.Feature.Run))
        {
            return;
        }

        var sets = CommandStore.CommandSets;
        var isFirst = sets.Count > 0 && sets[0].Id == commandSet.Id;
        var hasParallel = commandSet.ExecutableSessions.Count > 1;
        if (!isFirst || hasParallel)
        {
            throw Restriction();
        }
    }

    public static void ApplyAutoBanFromServer()
    {
        lock (Gate)
        {
            _cachedRevoked = true;
        }

        PersistRemoteState(true, DateTime.UtcNow);
        LicenseGuard.RefreshSentinel(false);
        AppEvents.RaiseLicenseChanged();
    }

    static RegistrationException Restriction()
    {
        if (AppLock.IsLocked)
        {
            return new RegistrationException(RegistrationErrorKind.UpdateRequired);
        }

        return new RegistrationException(IsRevoked ? RegistrationErrorKind.Revoked : RegistrationErrorKind.RegistrationRequired);
    }

    sealed class Record
    {
        public string Name { get; set; } = "";
        public string Email { get; set; } = "";
        public string Key { get; set; } = "";
        public string LicenseId { get; set; } = "";
        public bool? CachedRevoked { get; set; }
        public DateTime? LastSuccessfulRemoteCheck { get; set; }
    }

    static bool HasValidStoredKey => HasValidStoredLicense();

    static Record? ReadRecord()
    {
        var path = RegistrationFilePath;
        if (!File.Exists(path))
        {
            return null;
        }

        byte[] data;
        try
        {
            data = File.ReadAllBytes(path);
        }
        catch
        {
            return null;
        }

        if (data.Length == 0)
        {
            return null;
        }

        byte[] plaintext;
        try
        {
            plaintext = Decrypt(data);
        }
        catch
        {
            return null;
        }

        Record? record;
        try
        {
            record = JsonSerializer.Deserialize<Record>(plaintext, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }

        if (record == null)
        {
            return null;
        }

        lock (Gate)
        {
            _cachedRevoked = record.CachedRevoked;
            _lastSuccessfulRemoteCheck = record.LastSuccessfulRemoteCheck;
        }

        return record;
    }

    static void Write(Record record)
    {
        var path = RegistrationFilePath;
        AppStoragePaths.EnsureDirectory(Path.GetDirectoryName(path)!);
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(record, JsonOptions);
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, Encrypt(plaintext));
        File.Move(temp, path, overwrite: true);
    }

    static void ApplyRemoteResult(LicenseRemoteCheck.RemoteResult? remote, Record record)
    {
        if (remote == null)
        {
            return;
        }

        if (remote.Banned)
        {
            lock (Gate)
            {
                _cachedRevoked = true;
            }

            PersistRemoteState(true, DateTime.UtcNow);
            return;
        }

        lock (Gate)
        {
            _cachedRevoked = false;
            _lastSuccessfulRemoteCheck = DateTime.UtcNow;
        }

        PersistRemoteState(false, DateTime.UtcNow);
        LicenseGuard.RefreshSentinel(true);
        _ = record;
    }

    static void PersistRemoteState(bool revoked, DateTime checkedAt)
    {
        var record = ReadRecord();
        if (record == null)
        {
            return;
        }

        record.CachedRevoked = revoked;
        record.LastSuccessfulRemoteCheck = checkedAt;
        try
        {
            Write(record);
        }
        catch
        {
            // The in-memory revocation flag still applies for this session.
        }

        // ReadRecord loads the previous file contents and would clear a revocation
        // that was just applied. Put the persisted state back.
        lock (Gate)
        {
            _cachedRevoked = revoked;
            _lastSuccessfulRemoteCheck = checkedAt;
        }
    }

    static byte[] Encrypt(byte[] plaintext) => AesGcmCombined.Encrypt(RegistrationKeychain.FileKey(), plaintext);

    static byte[] Decrypt(byte[] data) => AesGcmCombined.Decrypt(RegistrationKeychain.FileKey(), data);

    static void EnsureNotAppLocked()
    {
        if (AppLock.IsLocked)
        {
            throw new RegistrationException(RegistrationErrorKind.UpdateRequired);
        }
    }

    static void EnsureIntegrityAllowsAccess()
    {
        if (LicenseGuard.IntegrityIssueOverride != null || LicenseGuard.RunIntegrityChecks() != null)
        {
            throw Restriction();
        }
    }
}
