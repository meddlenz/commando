using System.Globalization;
using System.Text;
using System.Text.Json;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace Commando.Licensing;

public static class LicenseKey
{
    const string Prefix = "COMMANDO1";
    const int Version = 1;
    const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public static byte[]? PublicKeyOverride { get; set; }

    public sealed class ParsedLicense
    {
        public required string Name { get; init; }
        public required string Email { get; init; }
        public required int Issued { get; init; }
        public required string Id { get; init; }
        public required int PayloadVersion { get; init; }
        public required byte[] PayloadBytes { get; init; }
        public required byte[] Signature { get; init; }
        public required string Wire { get; init; }
    }

    public static bool IsValid(string name, string email, string key)
    {
        var parsed = Parse(key);
        if (parsed == null)
        {
            return false;
        }

        var trimmedName = CanonicalName(name);
        var trimmedEmail = CanonicalEmail(email);
        if (parsed.PayloadVersion != Version
            || parsed.Name != trimmedName
            || parsed.Email != trimmedEmail
            || parsed.Id.Length == 0)
        {
            return false;
        }

        return VerifySignature(parsed.PayloadBytes, parsed.Signature);
    }

    public static string BanToken(string key)
    {
        var parsed = Parse(key);
        if (parsed != null)
        {
            return parsed.Id;
        }

        var normalizedKey = Normalized(key);
        return normalizedKey.Length >= 12 ? normalizedKey[^12..] : normalizedKey;
    }

    public static string? LicenseId(string key) => Parse(key)?.Id;

    public static ParsedLicense? Parse(string key)
    {
        var trimmed = key.Trim();
        var parts = trimmed.Split('.', StringSplitOptions.None);
        if (parts.Length != 3 || parts[0] != Prefix)
        {
            return null;
        }

        var payloadBytes = Base64UrlDecode(parts[1]);
        var signature = Base64UrlDecode(parts[2]);
        if (payloadBytes == null || signature == null)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(payloadBytes);
            var root = document.RootElement;
            if (!root.TryGetProperty("v", out var versionElement) || !versionElement.TryGetInt32(out var version))
            {
                return null;
            }

            if (!root.TryGetProperty("name", out var nameElement) || nameElement.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            if (!root.TryGetProperty("email", out var emailElement) || emailElement.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            if (!root.TryGetProperty("issued", out var issuedElement) || !issuedElement.TryGetInt32(out var issued))
            {
                return null;
            }

            if (!root.TryGetProperty("id", out var idElement) || idElement.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            return new ParsedLicense
            {
                PayloadVersion = version,
                Name = nameElement.GetString() ?? "",
                Email = emailElement.GetString() ?? "",
                Issued = issued,
                Id = idElement.GetString() ?? "",
                PayloadBytes = payloadBytes,
                Signature = signature,
                Wire = trimmed,
            };
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static string Generate(string name, string email, byte[] privateKeySeed, int? issued = null)
    {
        var trimmedName = CanonicalName(name);
        var trimmedEmail = CanonicalEmail(email);
        var issuedAt = issued ?? (int)DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var baseBytes = CanonicalPayloadBytes(trimmedName, trimmedEmail, issuedAt, "");
        var provisional = Sign(baseBytes, privateKeySeed);
        var licenseId = RecordId(provisional);
        var finalBytes = CanonicalPayloadBytes(trimmedName, trimmedEmail, issuedAt, licenseId);
        var finalSignature = Sign(finalBytes, privateKeySeed);
        return string.Join(".", Prefix, Base64UrlEncode(finalBytes), Base64UrlEncode(finalSignature));
    }

    public static string CanonicalName(string name) =>
        string.Join(" ", name.Trim().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    public static string CanonicalEmail(string email) => email.Trim().ToLowerInvariant();

    public static string Normalized(string key)
    {
        var builder = new StringBuilder();
        foreach (var character in key.ToUpperInvariant())
        {
            switch (character)
            {
                case '-':
                case ' ':
                case '\t':
                case '\n':
                    break;
                case 'I':
                case 'L':
                    builder.Append('1');
                    break;
                case 'O':
                    builder.Append('0');
                    break;
                default:
                    builder.Append(character);
                    break;
            }
        }

        return builder.ToString();
    }

    static byte[] CanonicalPayloadBytes(string name, string email, int issued, string id) =>
        Encoding.UTF8.GetBytes(CanonicalPayloadJson(name, email, issued, id));

    static string CanonicalPayloadJson(string name, string email, int issued, string id)
    {
        var parts = new List<string> { "\"email\":\"" + EscapeJson(email) + "\"" };
        if (id.Length > 0)
        {
            parts.Add("\"id\":\"" + EscapeJson(id) + "\"");
        }

        parts.Add("\"issued\":" + issued.ToString(CultureInfo.InvariantCulture));
        parts.Add("\"name\":\"" + EscapeJson(name) + "\"");
        parts.Add("\"v\":" + Version.ToString(CultureInfo.InvariantCulture));
        return "{" + string.Join(",", parts) + "}";
    }

    static bool VerifySignature(byte[] payloadBytes, byte[] signature)
    {
        var publicKeyData = PublicKeyOverride ?? LicenseSecrets.PublicKeyData;
        if (publicKeyData.Length != 32)
        {
            return false;
        }

        try
        {
            var publicKey = new Ed25519PublicKeyParameters(publicKeyData, 0);
            var verifier = new Ed25519Signer();
            verifier.Init(false, publicKey);
            verifier.BlockUpdate(payloadBytes, 0, payloadBytes.Length);
            return verifier.VerifySignature(signature);
        }
        catch
        {
            return false;
        }
    }

    static byte[] Sign(byte[] data, byte[] seed)
    {
        var privateKey = new Ed25519PrivateKeyParameters(seed, 0);
        var signer = new Ed25519Signer();
        signer.Init(true, privateKey);
        signer.BlockUpdate(data, 0, data.Length);
        return signer.GenerateSignature();
    }

    static string RecordId(byte[] signature)
    {
        var encoded = CrockfordEncode(signature);
        return encoded.Length >= 12 ? encoded[^12..] : encoded;
    }

    static string CrockfordEncode(byte[] bytes)
    {
        ulong buffer = 0;
        var bits = 0;
        var output = new StringBuilder();
        foreach (var value in bytes)
        {
            buffer = (buffer << 8) | value;
            bits += 8;
            while (bits >= 5)
            {
                bits -= 5;
                var index = (int)((buffer >> bits) & 31);
                output.Append(Alphabet[index]);
            }
        }

        if (bits > 0)
        {
            var index = (int)((buffer << (5 - bits)) & 31);
            output.Append(Alphabet[index]);
        }

        return output.ToString();
    }

    static string EscapeJson(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);

    static string Base64UrlEncode(byte[] data) =>
        Convert.ToBase64String(data).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    static byte[]? Base64UrlDecode(string value)
    {
        var base64 = value.Replace('-', '+').Replace('_', '/');
        var padding = (4 - (base64.Length % 4)) % 4;
        if (padding > 0)
        {
            base64 += new string('=', padding);
        }

        try
        {
            return Convert.FromBase64String(base64);
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
