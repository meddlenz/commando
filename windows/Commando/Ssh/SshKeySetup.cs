using Commando.Execution;
using Commando.Models;

namespace Commando.Ssh;

public static class SshKeySetup
{
    public sealed class SetupException : Exception
    {
        public SetupException(string message) : base(message)
        {
        }
    }

    public static string PrivateKeyPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ssh", "commando_ed25519");

    public static string PublicKeyPath => PrivateKeyPath + ".pub";

    public static string PrivateKeyPathForShell => PrivateKeyPath.Replace('\\', '/');

    public static bool HasLocalKey() => File.Exists(PublicKeyPath);

    public static void Install(SshConnection connection)
    {
        var remoteScript = """
            set -e
            umask 077
            mkdir -p ~/.ssh
            touch ~/.ssh/authorized_keys
            key=$(cat)
            grep -qxF "$key" ~/.ssh/authorized_keys || printf '%s\n' "$key" >> ~/.ssh/authorized_keys
            """;

        var sshCommand = SshShellCommand.BuildForPasswordAuth(connection, remoteScript);
        var destination = connection.Username + "@" + connection.Host;
        var keyPath = SshShellCommand.ShellQuote(PrivateKeyPathForShell);
        var publicKeyPath = SshShellCommand.ShellQuote(PublicKeyPath.Replace('\\', '/'));
        var keygen = FindKeygenForShell();
        var terminalCommand = $"""
            key_path={keyPath}
            public_key_path={publicKeyPath}
            ssh_keygen={SshShellCommand.ShellQuote(keygen)}
            mkdir -p "$(dirname "$key_path")"
            chmod 700 "$(dirname "$key_path")"
            if [ ! -f "$key_path" ]; then
              "$ssh_keygen" -t ed25519 -f "$key_path" -N '' -C commando
            fi
            if [ ! -f "$public_key_path" ]; then
              "$ssh_keygen" -y -f "$key_path" > "$public_key_path"
            fi
            chmod 600 "$key_path"
            chmod 644 "$public_key_path"
            /bin/cat "$public_key_path" | {sshCommand}
            printf '\nSSH key installed successfully on %s.\n' {SshShellCommand.ShellQuote(destination)}
            """;

        try
        {
            TerminalLauncher.Open(terminalCommand, "Set Up SSH Key", Commando.Preferences.TerminalAppSettings.SelectedAppPath);
        }
        catch (Exception ex)
        {
            throw new SetupException("Couldn't install SSH key on server: " + ex.Message);
        }
    }

    static string FindKeygenForShell()
    {
        var windows = Path.Combine(Environment.SystemDirectory, "OpenSSH", "ssh-keygen.exe");
        if (File.Exists(windows))
        {
            return windows.Replace('\\', '/');
        }

        return "ssh-keygen";
    }
}
