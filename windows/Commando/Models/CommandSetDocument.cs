using System.Text.Json;

namespace Commando.Models;

public static class CommandSetDocument
{
    public const int CurrentVersion = 1;

    public sealed class Payload
    {
        public Payload(int version, IReadOnlyList<CommandSet> commandSets)
        {
            Version = version;
            CommandSets = commandSets;
        }

        public int Version { get; }
        public IReadOnlyList<CommandSet> CommandSets { get; }
    }

    public sealed class DocumentException : Exception
    {
        public DocumentException(string message) : base(message)
        {
        }

        public static DocumentException UnsupportedVersion(int version) =>
            new($"This file was saved with a newer version of Commando ({version}). Update Commando to import it.");
    }

    public static byte[] Encode(IReadOnlyList<CommandSet> commandSets)
    {
        var payload = new Dictionary<string, object?>
        {
            ["version"] = CurrentVersion,
            ["commandSets"] = commandSets.Select(WriteSet).ToList(),
        };
        return JsonSerializer.SerializeToUtf8Bytes(payload, SerializerOptions);
    }

    public static string EncodeString(IReadOnlyList<CommandSet> commandSets) =>
        System.Text.Encoding.UTF8.GetString(Encode(commandSets));

    public static IReadOnlyList<CommandSet> Decode(byte[] data) => DecodePayload(data).CommandSets;

    public static Payload DecodePayload(byte[] data)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(data);
        }
        catch (JsonException)
        {
            throw new DocumentException("Command set file is not valid JSON.");
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("version", out _))
            {
                var version = root.TryGetProperty("version", out var versionElement) && versionElement.TryGetInt32(out var parsed)
                    ? parsed
                    : 0;
                if (version > CurrentVersion)
                {
                    throw DocumentException.UnsupportedVersion(version);
                }

                var sets = new List<CommandSet>();
                if (root.TryGetProperty("commandSets", out var setsElement) && setsElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in setsElement.EnumerateArray())
                    {
                        sets.Add(CommandSetJson.Read(item));
                    }
                }

                return new Payload(version, sets);
            }

            if (root.ValueKind == JsonValueKind.Array)
            {
                var sets = root.EnumerateArray().Select(CommandSetJson.Read).ToList();
                return new Payload(1, sets);
            }
        }

        throw new DocumentException("Command set file is not valid JSON.");
    }

    public static IReadOnlyList<CommandSet> DecodeStoredData(byte[] data)
    {
        try
        {
            var decrypted = Storage.SecureDataStore.Decrypt(data);
            return Decode(decrypted);
        }
        catch (DocumentException)
        {
            throw;
        }
        catch
        {
            return Decode(data);
        }
    }

    public static List<CommandSet> Merge(IReadOnlyList<CommandSet> existing, IReadOnlyList<CommandSet> imported)
    {
        var byId = new Dictionary<Guid, CommandSet>();
        var order = new List<Guid>();
        foreach (var commandSet in existing)
        {
            if (!byId.ContainsKey(commandSet.Id))
            {
                order.Add(commandSet.Id);
            }

            byId[commandSet.Id] = commandSet;
        }

        foreach (var commandSet in imported)
        {
            if (!byId.ContainsKey(commandSet.Id))
            {
                order.Add(commandSet.Id);
            }

            byId[commandSet.Id] = commandSet;
        }

        return order.Select(id => byId[id]).ToList();
    }

    static Dictionary<string, object?> WriteSet(CommandSet commandSet) => new()
    {
        ["id"] = commandSet.Id.ToString("D").ToUpperInvariant(),
        ["keepSessionOpen"] = commandSet.KeepSessionOpen,
        ["name"] = commandSet.Name,
        ["serverDetails"] = commandSet.ServerDetails,
        ["sessions"] = commandSet.Sessions.Select(session => new Dictionary<string, object?>
        {
            ["name"] = session.Name,
            ["steps"] = session.Steps,
        }).ToList(),
        ["steps"] = commandSet.Steps.ToList(),
    };

    static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
    };
}
