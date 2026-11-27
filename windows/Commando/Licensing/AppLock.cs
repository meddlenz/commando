namespace Commando.Licensing;

public static class AppLock
{
    public enum ReasonKind
    {
        UpdateRequired,
    }

    public sealed class LockReason
    {
        public LockReason(string minimumVersion, Uri? updateUrl)
        {
            MinimumVersion = minimumVersion;
            UpdateUrl = updateUrl;
        }

        public ReasonKind Kind => ReasonKind.UpdateRequired;
        public string MinimumVersion { get; }
        public Uri? UpdateUrl { get; }
    }

    public static LockReason? ReasonOverride { get; set; }

    public static LockReason? Reason { get; private set; }

    public static bool IsLocked => ReasonOverride != null || Reason != null;

    public static string UpdateRequiredMessage =>
        "This version of Commando is no longer supported. Please download and install the latest update to continue.";

    public static Uri? UpdateUrl => (ReasonOverride ?? Reason)?.UpdateUrl;

    public static void LockForUpdate(string minimumVersion, Uri? updateUrl)
    {
        Reason = new LockReason(minimumVersion, updateUrl);
    }

    public static void Clear()
    {
        Reason = null;
    }
}
