using Commando.Licensing;
using Commando.Models;
using Commando.Preferences;
using Commando.Ssh;

namespace Commando.Execution;

public static class CommandExecutor
{
    public sealed class ExecutionException : Exception
    {
        public ExecutionException(string message) : base(message)
        {
        }

        public static ExecutionException InvalidServer() =>
            new("Server must be username@host or username@host:port (without the ssh prefix).");

        public static ExecutionException NoSteps() =>
            new("This command has no steps to run.");

        public static ExecutionException Terminal(string message) => new(message);
    }

    public static void Run(CommandSet commandSet)
    {
        LicenseStatus.EnsureCanRun(commandSet);
        var commands = TerminalCommands(commandSet);
        var names = commandSet.ExecutableSessions.Select(session => session.Name).ToList();
        try
        {
            TerminalLauncher.Open(commands, commandSet.Name, names, TerminalAppSettings.SelectedAppPath);
        }
        catch (Exception ex) when (ex is not ExecutionException)
        {
            throw ExecutionException.Terminal(ex.Message);
        }
    }

    public static string TerminalCommand(CommandSet commandSet)
    {
        var commands = TerminalCommands(commandSet);
        if (commands.Count == 0)
        {
            throw ExecutionException.NoSteps();
        }

        return commands[0];
    }

    public static IReadOnlyList<string> TerminalCommands(CommandSet commandSet)
    {
        var serverDetails = SshConnection.Normalise(commandSet.ServerDetails);
        var sessions = commandSet.ExecutableSessions;
        var connection = SshConnection.Parse(serverDetails);
        if (connection != null)
        {
            return sessions.Select(session =>
            {
                var remoteSteps = RemoteSteps(session.NonEmptySteps, connection);
                var remoteScript = SshShellCommand.RemoteScript(remoteSteps, keepSessionOpen: true);
                var identity = SshKeySetup.HasLocalKey() ? SshKeySetup.PrivateKeyPathForShell : null;
                return SshShellCommand.Build(connection, remoteScript, interactive: true, identity);
            }).ToList();
        }

        if (serverDetails.Length > 0)
        {
            throw ExecutionException.InvalidServer();
        }

        if (sessions.Count == 0)
        {
            throw ExecutionException.NoSteps();
        }

        return sessions.Select(session => string.Join("\n", session.NonEmptySteps)).ToList();
    }

    static List<string> RemoteSteps(IReadOnlyList<string> steps, SshConnection connection)
    {
        var result = new List<string>();
        foreach (var step in steps)
        {
            var parsed = SshStepParser.ParseBareSshCommand(step);
            if (parsed != null
                && parsed.Username == connection.Username
                && parsed.Host == connection.Host
                && parsed.Port == connection.Port
                && SshStepParser.RemoteCommand(step) == null)
            {
                continue;
            }

            result.Add(step);
        }

        return result;
    }
}
