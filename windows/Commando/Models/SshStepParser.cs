namespace Commando.Models;

public static class SshStepParser
{
    static readonly HashSet<string> FlagsWithValue = new(StringComparer.Ordinal)
    {
        "-p", "-i", "-o", "-l", "-F", "-J", "-b", "-c", "-E", "-e", "-I", "-L", "-R", "-S", "-W", "-w",
    };

    public static SshConnection? ParseBareSshCommand(string command)
    {
        var tokens = Tokens(command);
        if (tokens.Count == 0 || tokens[0] != "ssh")
        {
            return null;
        }

        tokens.RemoveAt(0);
        int? port = null;

        while (tokens.Count > 0)
        {
            var token = tokens[0];
            if (token == "-p" && tokens.Count >= 2 && int.TryParse(tokens[1], out var parsedPort))
            {
                port = parsedPort;
                tokens.RemoveRange(0, 2);
                continue;
            }

            if (token.StartsWith('-'))
            {
                var flag = token == "-o" ? token : FlagOf(token);
                if (FlagsWithValue.Contains(flag) && tokens.Count >= 2 && !tokens[1].StartsWith('-'))
                {
                    tokens.RemoveRange(0, 2);
                }
                else
                {
                    tokens.RemoveAt(0);
                }

                continue;
            }

            break;
        }

        if (tokens.Count == 0)
        {
            return null;
        }

        var connection = SshConnection.Parse(tokens[0]);
        if (connection == null)
        {
            return null;
        }

        if (port != null)
        {
            return new SshConnection(connection.Username, connection.Host, port);
        }

        return connection;
    }

    public static string? RemoteCommand(string command)
    {
        var tokens = Tokens(command);
        if (tokens.Count == 0 || tokens[0] != "ssh")
        {
            return null;
        }

        tokens.RemoveAt(0);
        while (tokens.Count > 0)
        {
            var token = tokens[0];
            if (token == "-p" && tokens.Count >= 2)
            {
                tokens.RemoveRange(0, 2);
                continue;
            }

            if (token.StartsWith('-'))
            {
                var flag = token == "-o" ? token : FlagOf(token);
                if (FlagsWithValue.Contains(flag) && tokens.Count >= 2 && !tokens[1].StartsWith('-'))
                {
                    tokens.RemoveRange(0, 2);
                }
                else
                {
                    tokens.RemoveAt(0);
                }

                continue;
            }

            break;
        }

        if (tokens.Count == 0)
        {
            return null;
        }

        tokens.RemoveAt(0);
        if (tokens.Count == 0)
        {
            return null;
        }

        return string.Join(" ", tokens);
    }

    public static bool IsBareSshStep(string command) => ParseBareSshCommand(command) != null;

    static List<string> Tokens(string command) =>
        command.Trim().Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).ToList();

    static string FlagOf(string token)
    {
        var equals = token.IndexOf('=');
        return equals >= 0 ? token[..equals] : token;
    }
}
