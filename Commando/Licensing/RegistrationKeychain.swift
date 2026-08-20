//
//  RegistrationKeychain.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import CryptoKit
import Foundation

enum RegistrationKeychain {
    private static let keyFileName = "registration-device.key"

    static var keyOverride: SymmetricKey?

    static func fileKey() throws -> SymmetricKey {
        if let keyOverride {
            return keyOverride
        }

        let url = keyFileURL
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let generated = SymmetricKey(size: .bits256)
        let data = generated.withUnsafeBytes { Data($0) }
        try AppStoragePaths.ensureDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        return generated
    }

    static func resetKey() throws {
        try? FileManager.default.removeItem(at: keyFileURL)
    }

    private static var keyFileURL: URL {
        AppStoragePaths.applicationSupportDirectory.appendingPathComponent(keyFileName)
    }
}
