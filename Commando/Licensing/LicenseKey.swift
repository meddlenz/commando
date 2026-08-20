//
//  LicenseKey.swift
//  Commando
//  Jordan Trbuhovic 2026
//
//  THIS FILE MUST BE MIRRORED with the Keygen/LicenseKey.swift.
//  Both apps must generate and validate the same registration keys.
//

import CryptoKit
import Foundation

enum LicenseKey {
    private static let prefix = "COMMANDO1"
    private static let version = 1

    static var publicKeyOverride: Data?

    struct ParsedLicense {
        var payload: Payload
        var payloadBytes: Data
        var signature: Data
        var wire: String
    }

    struct Payload: Equatable {
        var version: Int
        var name: String
        var email: String
        var issued: Int
        var id: String
    }

    static func isValid(name: String, email: String, key: String) -> Bool {
        guard let parsed = parse(key) else {
            return false
        }

        let trimmedName = canonicalName(name)
        let trimmedEmail = canonicalEmail(email)

        guard parsed.payload.version == version,
              parsed.payload.name == trimmedName,
              parsed.payload.email == trimmedEmail,
              !parsed.payload.id.isEmpty else {
            return false
        }

        return verifySignature(payloadBytes: parsed.payloadBytes, signature: parsed.signature)
    }

    static func banToken(from key: String) -> String {
        if let parsed = parse(key) {
            return parsed.payload.id
        }

        let normalizedKey = normalized(key)
        guard normalizedKey.count >= 12 else {
            return normalizedKey
        }

        return String(normalizedKey.suffix(12))
    }

    static func licenseID(from key: String) -> String? {
        parse(key)?.payload.id
    }

    static func parse(_ key: String) -> ParsedLicense? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        guard parts.count == 3, parts[0] == prefix else {
            return nil
        }

        guard let payloadBytes = base64URLDecode(parts[1]),
              let signature = base64URLDecode(parts[2]),
              let payload = decodePayload(from: payloadBytes) else {
            return nil
        }

        return ParsedLicense(
            payload: payload,
            payloadBytes: payloadBytes,
            signature: signature,
            wire: trimmed
        )
    }

    static func generate(name: String, email: String, privateKey: Curve25519.Signing.PrivateKey, issued: Int = Int(Date().timeIntervalSince1970)) throws -> String {
        let trimmedName = canonicalName(name)
        let trimmedEmail = canonicalEmail(email)

        let basePayload = Payload(version: version, name: trimmedName, email: trimmedEmail, issued: issued, id: "")
        let baseBytes = try canonicalPayloadBytes(basePayload.withoutID)
        let provisionalSignature = try privateKey.signature(for: baseBytes)
        let licenseID = recordID(from: provisionalSignature)

        let finalPayload = Payload(version: version, name: trimmedName, email: trimmedEmail, issued: issued, id: licenseID)
        let finalBytes = try canonicalPayloadBytes(finalPayload)
        let finalSignature = try privateKey.signature(for: finalBytes)

        return [
            prefix,
            base64URLEncode(finalBytes),
            base64URLEncode(finalSignature),
        ].joined(separator: ".")
    }

    static func canonicalName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func canonicalEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalized(_ key: String) -> String {
        String(key.uppercased().compactMap { character -> Character? in
            switch character {
            case "-", " ", "\t", "\n":
                return nil
            case "I", "L":
                return "1"
            case "O":
                return "0"
            default:
                return character
            }
        })
    }

    static func canonicalPayloadBytes(_ payload: Payload) throws -> Data {
        guard let data = canonicalPayloadJSON(payload).data(using: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }

        return data
    }

    static func canonicalPayloadJSON(_ payload: Payload) -> String {
        var parts: [String] = []

        parts.append("\"email\":\"\(escapeJSON(payload.email))\"")
        if !payload.id.isEmpty {
            parts.append("\"id\":\"\(escapeJSON(payload.id))\"")
        }
        parts.append("\"issued\":\(payload.issued)")
        parts.append("\"name\":\"\(escapeJSON(payload.name))\"")
        parts.append("\"v\":\(payload.version)")

        return "{\(parts.joined(separator: ","))}"
    }

    private static func decodePayload(from data: Data) -> Payload? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["v"] as? Int,
              let name = object["name"] as? String,
              let email = object["email"] as? String,
              let issued = object["issued"] as? Int,
              let id = object["id"] as? String else {
            return nil
        }

        return Payload(version: version, name: name, email: email, issued: issued, id: id)
    }

    private static func verifySignature(payloadBytes: Data, signature: Data) -> Bool {
        guard let publicKeyData = publicKeyOverride ?? Optional(LicenseSecrets.publicKeyData),
              publicKeyData.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }

        return publicKey.isValidSignature(signature, for: payloadBytes)
    }

    private static func recordID(from signature: Data) -> String {
        let encoded = crockfordEncode(Array(signature))
        guard encoded.count >= 12 else {
            return encoded
        }

        return String(encoded.suffix(12))
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static func crockfordEncode(_ bytes: [UInt8]) -> String {
        var buffer: UInt = 0
        var bits = 0
        var output = ""

        for byte in bytes {
            buffer = (buffer << 8) | UInt(byte)
            bits += 8

            while bits >= 5 {
                bits -= 5
                let index = Int((buffer >> bits) & 31)
                output.append(alphabet[index])
            }
        }

        if bits > 0 {
            let index = Int((buffer << (5 - bits)) & 31)
            output.append(alphabet[index])
        }

        return output
    }

    private static func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = (4 - (base64.count % 4)) % 4
        base64.append(String(repeating: "=", count: padding))

        return Data(base64Encoded: base64)
    }
}

private extension LicenseKey.Payload {
    var withoutID: LicenseKey.Payload {
        LicenseKey.Payload(version: version, name: name, email: email, issued: issued, id: "")
    }
}
