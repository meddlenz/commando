//
//  LicenseStatus.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import CryptoKit
import Foundation

extension Notification.Name {
    static let licenseDidChange = Notification.Name("licenseDidChange")
}

enum LicenseStatus {
    enum RegistrationError: LocalizedError {
        case revoked
        case registrationRequired
        case missingFields
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .missingFields:
                return "Enter your full name, email, and registration key."
            case .invalidKey:
                return "That registration key does not match this name and email."
            case .registrationRequired:
                return "Please purchase Commando to unlock it's full capabilities."
            case .revoked:
                return "This license has been revoked. Please get in touch with Manticore Software."
            }
        }
    }

    private static let legacyNameKey = "licenseName"
    private static let legacyEmailKey = "licenseEmail"
    private static let legacyKeyKey = "licenseKey"

    static var isMacAppStoreOverride: Bool?
    static var isRevokedOverride: Bool?
    static var storageDirectoryOverride: URL?
    private static var cachedBanned: Bool?
    private static var banCheckID: UInt64 = 0

    static var registrationFileURL: URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride.appendingPathComponent(AppStoragePaths.registrationFileName)
        }

        return AppStoragePaths.registrationFileURL
    }

    static var isUnlocked: Bool {
        if isPurchasedFromAppStore {
            return true
        }

        if isRevoked {
            return false
        }

        return hasValidStoredKey
    }

    static var isPurchasedFromAppStore: Bool {
        isMacAppStoreOverride ?? AppDistribution.isMacAppStore
    }

    static var isRevoked: Bool {
        if isPurchasedFromAppStore {
            return false
        }

        return isRevokedOverride ?? (cachedBanned == true)
    }

    static var registeredLine: String? {
        if isRevoked {
            return nil
        }

        if hasValidStoredKey, let name = storedName, !name.isEmpty {
            return "Registered to: \(name)"
        }

        if isPurchasedFromAppStore {
            return "Purchased via the Mac App Store"
        }

        return nil
    }

    static var storedName: String? {
        storedRecord?.name
    }

    static func register(name: String, email: String, key: String) throws {
        let trimmedName = LicenseKey.canonicalName(name)
        let trimmedEmail = LicenseKey.canonicalEmail(email)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty, !trimmedKey.isEmpty else {
            throw RegistrationError.missingFields
        }

        guard LicenseKey.isValid(name: trimmedName, email: trimmedEmail, key: trimmedKey) else {
            throw RegistrationError.invalidKey
        }

        if LicenseBanCheck.isBanned(token: LicenseKey.banToken(from: trimmedKey)) {
            throw RegistrationError.revoked
        }

        try write(
            Record(
                name: trimmedName,
                email: trimmedEmail,
                key: LicenseKey.generate(name: trimmedName, email: trimmedEmail)
            )
        )
        cachedBanned = false
        banCheckID += 1
        clearLegacyDefaults()
        NotificationCenter.default.post(name: .licenseDidChange, object: nil)
    }

    static func clear() {
        banCheckID += 1
        cachedBanned = nil
        try? FileManager.default.removeItem(at: registrationFileURL)

        clearLegacyDefaults()
        NotificationCenter.default.post(name: .licenseDidChange, object: nil)
    }

    static func refreshBanStatus() {
        guard AppDistribution.usesDirectLicensing else {
            cachedBanned = false
            return
        }

        if isPurchasedFromAppStore {
            cachedBanned = false

            return
        }

        guard let record = storedRecord, LicenseKey.isValid(name: record.name, email: record.email, key: record.key) else {
            cachedBanned = nil
            return
        }

        let checkID = banCheckID
        DispatchQueue.global(qos: .utility).async {
           
            let banned = LicenseBanCheck.isBanned(token: LicenseKey.banToken(from: record.key))

            DispatchQueue.main.async {
                guard checkID == banCheckID else {
                    return
                }

                guard hasValidStoredKey else {
                    cachedBanned = nil
                    return
                }

                cachedBanned = banned
                NotificationCenter.default.post(name: .licenseDidChange, object: nil)
            }
        }
    }

    static func ensureCanAddCommandSet(existingCount: Int) throws {
        guard AppDistribution.usesDirectLicensing, !isUnlocked, existingCount >= 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanAddSession() throws {
        guard AppDistribution.usesDirectLicensing, !isUnlocked else {
            return
        }

        throw restrictionError
    }

    static func ensureCanSaveSessions(_ count: Int) throws {
        guard AppDistribution.usesDirectLicensing, !isUnlocked, count > 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanImport(resultingCount: Int) throws {
        guard AppDistribution.usesDirectLicensing, !isUnlocked, resultingCount > 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanRun(commandSet: CommandSet) throws {
        guard AppDistribution.usesDirectLicensing, !isUnlocked else {
            return
        }

        let isFirstCommandSet = CommandStore.commandSets.first?.id == commandSet.id
        let hasParallelSessions = commandSet.executableSessions.count > 1

        guard isFirstCommandSet, !hasParallelSessions else {
            throw restrictionError
        }
    }

    private static var restrictionError: RegistrationError {
        isRevoked ? .revoked : .registrationRequired
    }

    private struct Record: Codable {
        var name: String
        var email: String
        var key: String
    }

    private static var hasValidStoredKey: Bool {
        guard let record = storedRecord else {
            return false
        }

        return LicenseKey.isValid(name: record.name, email: record.email, key: record.key)
    }

    private static var storedRecord: Record? {
        migrateLegacyDefaultsIfNeeded()

        return readRecord()
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        guard storageDirectoryOverride == nil else {
            return
        }

        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyNameKey) != nil
            || defaults.object(forKey: legacyEmailKey) != nil
            || defaults.object(forKey: legacyKeyKey) != nil else {
            return
        }

        if readRecord() == nil,
           let name = defaults.string(forKey: legacyNameKey),
           let email = defaults.string(forKey: legacyEmailKey),
           let key = defaults.string(forKey: legacyKeyKey),
           LicenseKey.isValid(name: name, email: email, key: key) {
            try? write(
                Record(
                    name: LicenseKey.canonicalName(name),
                    email: LicenseKey.canonicalEmail(email),
                    key: LicenseKey.generate(name: name, email: email)
                )
            )
        }

        clearLegacyDefaults()
    }

    private static func readRecord() -> Record? {
        let url = registrationFileURL

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }

        guard let plaintext = try? decrypt(data) else {
            return nil
        }

        return try? JSONDecoder().decode(Record.self, from: plaintext)
    }

    private static func write(_ record: Record) throws {
        let url = registrationFileURL
        try AppStoragePaths.ensureDirectory(at: url.deletingLastPathComponent())
        let plaintext = try JSONEncoder().encode(record)
        try encrypt(plaintext).write(to: url, options: .atomic)
    }

    private static func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: fileKey())
        
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }

        return combined
    }

    private static func decrypt(_ data: Data) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: fileKey())
    }

    private static func fileKey() -> SymmetricKey {
        let material = Data(LicenseSecrets.secret.utf8) + Data("commando.registration.v1".utf8)
        return SymmetricKey(data: Data(SHA256.hash(data: material)))
    }

    private static func clearLegacyDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyNameKey)
        defaults.removeObject(forKey: legacyEmailKey)
        defaults.removeObject(forKey: legacyKeyKey)
    }
}
