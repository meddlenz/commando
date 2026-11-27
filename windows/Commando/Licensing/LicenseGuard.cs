using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Commando.Storage;

namespace Commando.Licensing;

public static class LicenseGuard
{
    public enum Feature
    {
        Run,
        ImportSets,
        AddCommandSet,
        AddSession,
        Register,
        General,
    }

    public enum IntegrityIssue
    {
        CodesignInvalid,
        UnlockMismatch,
        TamperedSentinel,
    }

    const string SentinelFileName = "license-sentinel.dat";

    public static IntegrityIssue? IntegrityIssueOverride { get; set; }
    public static bool SkipIntegrityChecks { get; set; }
    public static string? StorageDirectoryOverride { get; set; }

    public static bool Permits(Feature feature)
    {
        if (AppLock.IsLocked)
        {
            return false;
        }

        if (IntegrityIssueOverride != null)
        {
            return false;
        }

        if (!SkipIntegrityChecks && RunIntegrityChecks() is { } issue)
        {
            ReportIntegrityIssue(issue);
            return false;
        }

        return feature switch
        {
            Feature.Register => !LicenseStatus.IsRevoked,
            Feature.General => true,
            _ => LicenseStatus.IsUnlocked,
        };
    }

    public static IntegrityIssue? RunIntegrityChecks()
    {
        if (SkipIntegrityChecks)
        {
            return null;
        }

        if (!VerifyCodesignIntegrity())
        {
            return IntegrityIssue.CodesignInvalid;
        }

        var cryptographicallyUnlocked = LicenseStatus.HasValidStoredLicense();
        var sentinelMatches = SentinelMatchesUnlockState(cryptographicallyUnlocked);
        if (cryptographicallyUnlocked != LicenseStatus.IsUnlockedPublicState)
        {
            return IntegrityIssue.UnlockMismatch;
        }

        if (!sentinelMatches)
        {
            return IntegrityIssue.TamperedSentinel;
        }

        return null;
    }

    public static void RefreshSentinel(bool unlocked)
    {
        var token = SentinelToken(unlocked);
        var path = SentinelFilePath;
        try
        {
            AppStoragePaths.EnsureDirectory(Path.GetDirectoryName(path)!);
            var temp = path + ".tmp";
            File.WriteAllBytes(temp, token);
            File.Move(temp, path, overwrite: true);
        }
        catch
        {
            if (!unlocked && File.Exists(path))
            {
                try
                {
                    File.Delete(path);
                }
                catch
                {
                    // The next gated action will notice a missing sentinel.
                }
            }
        }
    }

    public static bool VerifyCodesignIntegrity()
    {
        try
        {
            var path = Environment.ProcessPath;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return true;
            }

            try
            {
                using var _ = X509Certificate.CreateFromSignedFile(path);
            }
            catch (CryptographicException)
            {
                return true;
            }

            return WinTrust.VerifyEmbeddedSignature(path);
        }
        catch
        {
            return true;
        }
    }

    public static void ReportIntegrityIssue(IntegrityIssue issue)
    {
        var token = LicenseStatus.StoredLicenseId;
        if (!string.IsNullOrEmpty(token))
        {
            LicenseRemoteCheck.ReportTamper(token, IssueDetail(issue), AppInfo.ShortVersion);
        }
    }

    static string IssueDetail(IntegrityIssue issue) => issue switch
    {
        IntegrityIssue.CodesignInvalid => "codesign_invalid",
        IntegrityIssue.UnlockMismatch => "unlock_mismatch",
        _ => "sentinel_mismatch",
    };

    static bool SentinelMatchesUnlockState(bool unlocked)
    {
        var expected = SentinelToken(unlocked);
        var path = SentinelFilePath;
        if (!File.Exists(path))
        {
            return !unlocked;
        }

        try
        {
            return File.ReadAllBytes(path).AsSpan().SequenceEqual(expected);
        }
        catch
        {
            return false;
        }
    }

    static byte[] SentinelToken(bool unlocked)
    {
        var marker = unlocked ? "unlocked" : "locked";
        return SHA256.HashData(Encoding.UTF8.GetBytes("commando.sentinel.v1" + marker));
    }

    static string SentinelFilePath =>
        Path.Combine(StorageDirectoryOverride ?? AppStoragePaths.ApplicationSupportDirectory, SentinelFileName);
}

static class WinTrust
{
    const uint WtdUiNone = 2;
    const uint WtdRevokeNone = 0;
    const uint WtdChoiceFile = 1;
    const uint WtdStateActionVerify = 1;
    const uint WtdStateActionClose = 2;

    static readonly Guid ActionGenericVerify = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

    public static bool VerifyEmbeddedSignature(string path)
    {
        var fileInfo = new WinTrustFileInfo
        {
            StructSize = (uint)Marshal.SizeOf<WinTrustFileInfo>(),
            FilePath = path,
        };
        var filePointer = Marshal.AllocHGlobal(Marshal.SizeOf<WinTrustFileInfo>());
        try
        {
            Marshal.StructureToPtr(fileInfo, filePointer, false);
            var data = new WinTrustData
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustData>(),
                UIChoice = WtdUiNone,
                RevocationChecks = WtdRevokeNone,
                UnionChoice = WtdChoiceFile,
                FileInfo = filePointer,
                StateAction = WtdStateActionVerify,
            };
            var action = ActionGenericVerify;
            var result = WinVerifyTrust(IntPtr.Zero, ref action, ref data);
            data.StateAction = WtdStateActionClose;
            WinVerifyTrust(IntPtr.Zero, ref action, ref data);
            return result == 0;
        }
        finally
        {
            Marshal.FreeHGlobal(filePointer);
        }
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern int WinVerifyTrust(IntPtr hwnd, ref Guid actionId, ref WinTrustData data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WinTrustFileInfo
    {
        public uint StructSize;
        public string FilePath;
        public IntPtr FileHandle;
        public IntPtr KnownSubject;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WinTrustData
    {
        public uint StructSize;
        public IntPtr PolicyCallbackData;
        public IntPtr SIPClientData;
        public uint UIChoice;
        public uint RevocationChecks;
        public uint UnionChoice;
        public IntPtr FileInfo;
        public uint StateAction;
        public IntPtr StateData;
        public string? UrlReference;
        public uint ProvFlags;
        public uint UIContext;
        public IntPtr SignatureSettings;
    }
}
