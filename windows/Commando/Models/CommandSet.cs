using System.Globalization;
using System.Text.Json;

namespace Commando.Models;

public sealed class CommandSession
{
    public CommandSession(string name = "", IReadOnlyList<string>? steps = null)
    {
        Name = name;
        var values = steps?.ToList() ?? new List<string>();
        Steps = values.Count == 0 ? new List<string> { "" } : values;
    }

    public string Name { get; set; }
    public List<string> Steps { get; set; }

    public IReadOnlyList<string> NonEmptySteps =>
        Steps.Select(step => step.Trim()).Where(step => step.Length > 0).ToList();
}

public sealed class CommandSet
{
    public CommandSet(
        string name,
        string serverDetails = "",
        IReadOnlyList<string>? steps = null,
        IReadOnlyList<CommandSession>? sessions = null,
        Guid? id = null,
        bool keepSessionOpen = true)
    {
        Id = id ?? Guid.NewGuid();
        Name = name;
        ServerDetails = serverDetails;
        KeepSessionOpen = keepSessionOpen;
        Sessions = Normalize(sessions ?? new[] { new CommandSession(steps: steps ?? new List<string> { "" }) });
    }

    public Guid Id { get; }
    public string Name { get; }
    public string ServerDetails { get; }
    public List<CommandSession> Sessions { get; }
    public bool KeepSessionOpen { get; }

    public IReadOnlyList<string> Steps => Sessions.Count > 0 ? Sessions[0].Steps : new List<string> { "" };

    public IReadOnlyList<string> NonEmptySteps => NonEmptySessions.SelectMany(session => session).ToList();

    public IReadOnlyList<IReadOnlyList<string>> NonEmptySessions =>
        ExecutableSessions.Select(session => session.NonEmptySteps).Where(steps => steps.Count > 0).ToList();

    public IReadOnlyList<CommandSession> ExecutableSessions
    {
        get
        {
            var sessions = new List<CommandSession>();
            foreach (var session in Sessions)
            {
                var steps = session.NonEmptySteps.ToList();
                if (steps.Count == 0)
                {
                    continue;
                }

                sessions.Add(new CommandSession(session.Name, steps));
            }

            if (sessions.Count > 0)
            {
                return sessions;
            }

            if (!IsRemote)
            {
                return Array.Empty<CommandSession>();
            }

            var name = Sessions.Count > 0 ? Sessions[0].Name : "";
            return new[] { new CommandSession(name, Array.Empty<string>()) };
        }
    }

    public string StepsSummary
    {
        get
        {
            var sessions = NonEmptySessions;
            if (sessions.Count > 1)
            {
                return $"{sessions.Count} sessions";
            }

            var commands = sessions.Count > 0 ? sessions[0] : Array.Empty<string>();
            if (commands.Count == 0)
            {
                return "No steps";
            }

            if (commands.Count == 1)
            {
                return commands[0];
            }

            return $"{commands.Count} steps";
        }
    }

    public bool IsRemote => ServerDetails.Trim().Length > 0;

    public string MenuSubtitle => IsRemote ? ServerDetails : StepsSummary;

    public CommandSet Clone() =>
        new(Name, ServerDetails, sessions: Sessions.Select(session => new CommandSession(session.Name, session.Steps.ToList())).ToList(), id: Id, keepSessionOpen: KeepSessionOpen);

    static List<CommandSession> Normalize(IReadOnlyList<CommandSession> sessions)
    {
        var normalised = sessions
            .Select(session => new CommandSession(session.Name, session.Steps.Count == 0 ? new List<string> { "" } : session.Steps.ToList()))
            .ToList();
        return normalised.Count == 0 ? new List<CommandSession> { new() } : normalised;
    }
}

public static class ExampleCommandSet
{
    public static readonly Guid Id = Guid.Parse("E0000000-0000-4000-8000-C00000000001");

    public static CommandSet HelloWorld => new("Hello World", steps: new[] { "echo 'Hello, World!'" }, id: Id);

    public static void InstallIfNeeded()
    {
        if (Storage.Preferences.ExampleCommandSetRemoved)
        {
            return;
        }

        if (Storage.CommandStore.CommandSets.Count > 0)
        {
            return;
        }

        Storage.CommandStore.CommandSets = new List<CommandSet> { HelloWorld };
    }

    public static void MarkRemovedIfNeeded(Guid id)
    {
        if (id != Id)
        {
            return;
        }

        Storage.Preferences.ExampleCommandSetRemoved = true;
    }
}

public static class CommandSetJson
{
    public static CommandSet Read(JsonElement root)
    {
        var id = Guid.NewGuid();
        if (root.TryGetProperty("id", out var idElement)
            && idElement.ValueKind == JsonValueKind.String
            && Guid.TryParse(idElement.GetString(), out var parsed))
        {
            id = parsed;
        }

        var name = root.TryGetProperty("name", out var nameElement) && nameElement.ValueKind == JsonValueKind.String
            ? nameElement.GetString() ?? "New Command"
            : "New Command";
        var server = root.TryGetProperty("serverDetails", out var serverElement) && serverElement.ValueKind == JsonValueKind.String
            ? serverElement.GetString() ?? ""
            : "";
        var keep = true;
        if (root.TryGetProperty("keepSessionOpen", out var keepElement)
            && (keepElement.ValueKind == JsonValueKind.True || keepElement.ValueKind == JsonValueKind.False))
        {
            keep = keepElement.GetBoolean();
        }

        List<CommandSession> sessions;
        if (root.TryGetProperty("sessions", out var sessionsElement)
            && sessionsElement.ValueKind == JsonValueKind.Array
            && sessionsElement.GetArrayLength() > 0)
        {
            sessions = sessionsElement.EnumerateArray().Select(ReadSession).ToList();
        }
        else
        {
            sessions = new List<CommandSession> { new("", ReadLegacySteps(root)) };
        }

        return new CommandSet(name, server, sessions: sessions, id: id, keepSessionOpen: keep);
    }

    static CommandSession ReadSession(JsonElement item)
    {
        if (item.ValueKind == JsonValueKind.Array)
        {
            return new CommandSession("", item.EnumerateArray().Select(step => step.GetString() ?? "").ToList());
        }

        var name = item.TryGetProperty("name", out var nameElement) && nameElement.ValueKind == JsonValueKind.String
            ? nameElement.GetString() ?? ""
            : "";
        if (item.TryGetProperty("steps", out var stepsElement) && stepsElement.ValueKind == JsonValueKind.Array)
        {
            return new CommandSession(name, stepsElement.EnumerateArray().Select(step => step.GetString() ?? "").ToList());
        }

        return new CommandSession(name, new List<string> { "" });
    }

    static List<string> ReadLegacySteps(JsonElement root)
    {
        if (root.TryGetProperty("steps", out var steps) && steps.ValueKind == JsonValueKind.Array && steps.GetArrayLength() > 0)
        {
            var first = steps[0];
            if (first.ValueKind == JsonValueKind.String)
            {
                var values = steps.EnumerateArray().Select(step => step.GetString() ?? "").ToList();
                return values.Count == 0 ? new List<string> { "" } : values;
            }

            if (first.ValueKind == JsonValueKind.Object)
            {
                var values = new List<string>();
                foreach (var step in steps.EnumerateArray())
                {
                    var text = CommandText(step);
                    if (text != null)
                    {
                        values.Add(text);
                    }
                }

                return values.Count == 0 ? new List<string> { "" } : values;
            }
        }

        if (root.TryGetProperty("commands", out var commands) && commands.ValueKind == JsonValueKind.Array && commands.GetArrayLength() > 0)
        {
            return commands.EnumerateArray().Select(step => step.GetString() ?? "").ToList();
        }

        return new List<string> { "" };
    }

    static string? CommandText(JsonElement step)
    {
        var text = step.TryGetProperty("text", out var textElement) && textElement.ValueKind == JsonValueKind.String
            ? textElement.GetString() ?? ""
            : "";
        var trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var kind = step.TryGetProperty("kind", out var kindElement) && kindElement.ValueKind == JsonValueKind.String
            ? kindElement.GetString()
            : null;
        if (kind == "delay")
        {
            if (!double.TryParse(trimmed, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) || seconds <= 0)
            {
                return null;
            }

            if (Math.Abs(seconds - Math.Round(seconds)) < 0.0000001)
            {
                return "sleep " + ((int)Math.Round(seconds)).ToString(CultureInfo.InvariantCulture);
            }

            return "sleep " + seconds.ToString(CultureInfo.InvariantCulture);
        }

        return trimmed;
    }
}
