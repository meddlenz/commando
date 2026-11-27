using System.Runtime.InteropServices;

namespace Commando.Storage;

public static class CredentialStore
{
    public const string StorageService = "manticoresw.Commando.storage";
    const string PasswordService = "manticoresw.Commando.ssh-password";
    const int CredTypeGeneric = 1;
    const int CredPersistLocalMachine = 2;

    public static void DeletePassword(Guid commandSetId)
    {
        DeleteSecret(PasswordService, commandSetId.ToString("D").ToUpperInvariant());
    }

    public static byte[]? ReadSecret(string service, string account)
    {
        if (!CredRead(Target(service, account), CredTypeGeneric, 0, out var pointer))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return Array.Empty<byte>();
            }

            var data = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, data, 0, data.Length);
            return data;
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public static void WriteSecret(string service, string account, byte[] secret)
    {
        var blob = Marshal.AllocHGlobal(secret.Length);
        try
        {
            Marshal.Copy(secret, 0, blob, secret.Length);
            var credential = new NativeCredential
            {
                Type = CredTypeGeneric,
                TargetName = Target(service, account),
                CredentialBlobSize = (uint)secret.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = account,
            };

            if (!CredWrite(ref credential, 0))
            {
                throw new InvalidOperationException("Could not store a secret in Windows Credential Manager.");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    public static void DeleteSecret(string service, string account)
    {
        CredDelete(Target(service, account), CredTypeGeneric, 0);
    }

    static string Target(string service, string account) => service + ":" + account;

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWrite([In] ref NativeCredential credential, uint flags);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credential);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr credential);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NativeCredential
    {
        public uint Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }
}
