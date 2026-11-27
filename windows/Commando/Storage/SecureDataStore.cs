using System.Security.Cryptography;

namespace Commando.Storage;

public static class SecureDataStore
{
    const string KeyAccount = "commandSetsEncryptionKey";

    public static byte[]? KeyOverride { get; set; }

    public static byte[] Encrypt(byte[] plaintext) => AesGcmCombined.Encrypt(SymmetricKey(), plaintext);

    public static byte[] Decrypt(byte[] ciphertext) => AesGcmCombined.Decrypt(SymmetricKey(), ciphertext);

    static byte[] SymmetricKey()
    {
        if (KeyOverride is { Length: 32 } overrideKey)
        {
            return overrideKey;
        }

        var existing = CredentialStore.ReadSecret(CredentialStore.StorageService, KeyAccount);
        if (existing is { Length: 32 })
        {
            return existing;
        }

        var created = RandomNumberGenerator.GetBytes(32);
        CredentialStore.WriteSecret(CredentialStore.StorageService, KeyAccount, created);
        return created;
    }
}
