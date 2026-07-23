//
//  KeychainCredentialStore.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation
import Security

enum KeychainCredentialStore {
    static let storageService = "manticoresw.Commando.storage"
    private static let passwordService = "manticoresw.Commando.ssh-password"

    static func deletePassword(for commandSetID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: passwordService,
            kSecAttrAccount as String: commandSetID.uuidString,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
