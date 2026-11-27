namespace Commando.Storage;

public static class AppStoragePaths
{
    public const string CommandSetsFileName = "command-sets.json";
    public const string RegistrationFileName = "registration.dat";
    public const string ICloudContainerIdentifier = "iCloud.com.manticoresw.commando";

    public static string ApplicationSupportDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Commando");

    public static string LocalCommandSetsFile =>
        Path.Combine(ApplicationSupportDirectory, CommandSetsFileName);

    public static string RegistrationFile =>
        Path.Combine(ApplicationSupportDirectory, RegistrationFileName);

    public static string TerminalRunsDirectory =>
        Path.Combine(ApplicationSupportDirectory, "terminal-runs");

    public static string? ICloudDriveRoot
    {
        get
        {
            var root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "iCloudDrive");
            return Directory.Exists(root) ? root : null;
        }
    }

    public static string? ICloudCommandSetsFile
    {
        get
        {
            var root = ICloudDriveRoot;
            if (root == null)
            {
                return null;
            }

            return Path.Combine(root, "Commando", "Documents", CommandSetsFileName);
        }
    }

    public static void EnsureDirectory(string directory)
    {
        Directory.CreateDirectory(directory);
    }
}
