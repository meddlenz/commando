using System.Security.Cryptography;
using Commando.Storage;

namespace Commando.Licensing;

public static class RegistrationKeychain
{
    const string KeyFileName = "registration-device.key";

    public static byte[]? KeyOverride { get; set; }

    public static byte[] FileKey()
    {
        if (KeyOverride is { Length: 32 } overrideKey)
        {
            return overrideKey;
        }

        var path = KeyFilePath;
        if (File.Exists(path))
        {
            var existing = File.ReadAllBytes(path);
            if (existing.Length == 32)
            {
                return existing;
            }
        }

        var generated = RandomNumberGenerator.GetBytes(32);
        AppStoragePaths.EnsureDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, generated);
        File.Move(temp, path, overwrite: true);
        return generated;
    }

    public static void ResetKey()
    {
        if (File.Exists(KeyFilePath))
        {
            File.Delete(KeyFilePath);
        }
    }

    static string KeyFilePath => Path.Combine(AppStoragePaths.ApplicationSupportDirectory, KeyFileName);
}
