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
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func generate(name: String, email: String) -> String {
        format(encode(hmacBytes(name: name, email: email)))
    }

    static func isValid(name: String, email: String, key: String) -> Bool {
        let expected = normalized(generate(name: name, email: email))
        let actual = normalized(key)

        guard expected.count == actual.count, !expected.isEmpty else {
            return false
        }

        return constantTimeEquals(expected, actual)
    }

    static func banToken(from key: String) -> String {
        let normalizedKey = normalized(key)

        guard normalizedKey.count >= 12 else {

            return normalizedKey
        }

        return String(normalizedKey.suffix(12))
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

    private static func hmacBytes(name: String, email: String) -> [UInt8] {
        let payload = canonicalEmail(email) + "\n" + canonicalName(name)
        let key = SymmetricKey(data: Data(LicenseSecrets.secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)

        return Array(Data(mac).prefix(16))
    }

    private static func encode(_ bytes: [UInt8]) -> String {
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

    private static func format(_ encoded: String) -> String {
        stride(from: 0, to: encoded.count, by: 5).map { start in
            let from = encoded.index(encoded.startIndex, offsetBy: start)
            let to = encoded.index(from, offsetBy: 5, limitedBy: encoded.endIndex) ?? encoded.endIndex
            
            return String(encoded[from..<to])
        }
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    }

    private static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)

        guard leftBytes.count == rightBytes.count else {
            return false
        }

        var difference: UInt8 = 0
        
        for index in leftBytes.indices {
            difference |= leftBytes[index] ^ rightBytes[index]
        }

        return difference == 0
    }
}
