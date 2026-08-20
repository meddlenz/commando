//
//  RegistrationKeychain.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import CryptoKit
import Foundation
import Security

enum RegistrationKeychain {
    private static let service = "com.manticoresw.commando.registration"
    private static let account = "fileKey"

    static var keyOverride: SymmetricKey?

    static func fileKey() throws -> SymmetricKey {
        if let keyOverride {
            return keyOverride
        }

        if let existing = try loadKey() {
            return existing
        }

        let generated = SymmetricKey(size: .bits256)
        try saveKey(generated)
        return generated
    }

    static func resetKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }

    private static func loadKey() throws -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw CocoaError(.fileReadUnknown)
        }

        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
