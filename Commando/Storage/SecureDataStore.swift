//
//  SecureDataStore.swift
//  Commando
//

import CryptoKit
import Foundation
import Security

enum SecureDataStore {
    private static let keyAccount = "commandSetsEncryptionKey"

    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw StoreError.encryptionFailed
        }
        return combined
    }

    static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try symmetricKey()
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func symmetricKey() throws -> SymmetricKey {
        if let existing = try loadKey() {
            return SymmetricKey(data: existing)
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw StoreError.keychainError(status)
        }

        let keyData = Data(keyBytes)
        try saveKey(keyData)
        return SymmetricKey(data: keyData)
    }

    private static func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainCredentialStore.storageService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.keychainError(status)
        }

        return data
    }

    private static func saveKey(_ keyData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainCredentialStore.storageService,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.keychainError(status)
        }
    }

    enum StoreError: Error {
        case encryptionFailed
        case keychainError(OSStatus)
    }
}
