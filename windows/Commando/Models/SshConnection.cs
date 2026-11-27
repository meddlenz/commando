namespace Commando.Models;

public sealed class SshConnection
{
    public SshConnection(string username, string host, int? port)
    {
        Username = username;
        Host = host;
        Port = port;
    }

    public string Username { get; }
    public string Host { get; }
    public int? Port { get; }

    public static string Normalise(string serverDetails)
    {
        var trimmed = serverDetails.Trim();
        if (trimmed.StartsWith("ssh ", StringComparison.Ordinal))
        {
            trimmed = trimmed[4..].Trim();
        }

        return trimmed;
    }

    public static SshConnection? Parse(string serverDetails)
    {
        var trimmed = Normalise(serverDetails);
        if (trimmed.Length == 0)
        {
            return null;
        }

        var at = trimmed.LastIndexOf('@');
        if (at < 0)
        {
            return null;
        }

        var username = trimmed[..at].Trim();
        var hostPart = trimmed[(at + 1)..].Trim();
        if (username.Length == 0 || hostPart.Length == 0 || username.Contains(' '))
        {
            return null;
        }

        var colon = hostPart.LastIndexOf(':');
        if (colon >= 0
            && colon < hostPart.Length - 1
            && hostPart[(colon + 1)..].All(char.IsDigit))
        {
            var host = hostPart[..colon];
            if (host.Length == 0 || !int.TryParse(hostPart[(colon + 1)..], out var port))
            {
                return null;
            }

            return new SshConnection(username, host, port);
        }

        return new SshConnection(username, hostPart, null);
    }
}
