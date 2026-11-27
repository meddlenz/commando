using System.Text;
using Commando.Models;

namespace Commando.Ssh;

public static class SshShellCommand
{
    public static string Build(
        SshConnection connection,
        string? remoteScript = null,
        bool interactive = false,
        string? identityFile = null)
    {
        return BuildInvocation(connection, remoteScript, interactive, identityFile, passwordAuth: false, strictHostKeyChecking: "accept-new");
    }

    public static string BuildForPasswordAuth(
        SshConnection connection,
        string? remoteScript = null,
        bool interactive = false)
    {
        return BuildInvocation(connection, remoteScript, interactive, identityFile: null, passwordAuth: true, strictHostKeyChecking: "ask");
    }

    public static string? RemoteScript(IReadOnlyList<string> steps, bool keepSessionOpen)
    {
        if (steps.Count == 0)
        {
            return keepSessionOpen ? "exec bash -i </dev/tty" : null;
        }

        var lines = new List<string> { "set -e" };
        lines.AddRange(steps);
        if (keepSessionOpen)
        {
            lines.Add("exec bash -i </dev/tty");
        }

        return string.Join("\n", lines);
    }

    public static string ShellQuote(string value) => "'" + value.Replace("'", "'\\''") + "'";

    static string BuildInvocation(
        SshConnection connection,
        string? remoteScript,
        bool interactive,
        string? identityFile,
        bool passwordAuth,
        string strictHostKeyChecking)
    {
        var sshLine = "ssh -o StrictHostKeyChecking=" + strictHostKeyChecking;
        if (passwordAuth)
        {
            sshLine += " -o PreferredAuthentications=password,keyboard-interactive";
            sshLine += " -o PubkeyAuthentication=no";
        }
        else if (!string.IsNullOrEmpty(identityFile))
        {
            sshLine += " -o IdentitiesOnly=yes -i " + ShellQuote(identityFile);
        }

        if (interactive)
        {
            sshLine += " -t";
        }

        if (connection.Port != null)
        {
            sshLine += " -p " + connection.Port.Value.ToString();
        }

        sshLine += " " + ShellQuote(connection.Username + "@" + connection.Host);

        if (string.IsNullOrEmpty(remoteScript))
        {
            return sshLine;
        }

        var encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(remoteScript));
        var remoteCommand =
            "f=$(mktemp /tmp/commandrunner.XXXXXX.sh) && echo "
            + encoded
            + " | base64 -d > \"$f\" && bash \"$f\"; e=$?; rm -f \"$f\"; exit $e";
        return sshLine + " " + ShellQuote(remoteCommand);
    }
}
