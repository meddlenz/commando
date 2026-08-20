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
        case updateRequired

        var errorDescription: String? {
            switch self {
            case .missingFields:
                return "Enter your full name, email, and license key."
            case .invalidKey:
                return "That license key does not match this name and email."
            case .registrationRequired:
                return "Please purchase Commando to unlock its full capabilities."
            case .revoked:
                return "This license has been revoked. Please get in touch with Manticore SW for more information."
            case .updateRequired:
                return AppLock.updateRequiredMessage
            }
        }
    }

    static var isRevokedOverride: Bool?
    static var storageDirectoryOverride: URL?
    private static var cachedRevoked: Bool?
    private static var lastSuccessfulRemoteCheck: Date?
    private static var remoteCheckID: UInt64 = 0

    static var registrationFileURL: URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride.appendingPathComponent(AppStoragePaths.registrationFileName)
        }

        return AppStoragePaths.registrationFileURL
    }

    static var isUnlocked: Bool {
        isUnlockedPublicState
    }

    static var isUnlockedPublicState: Bool {
        if AppLock.isLocked {
            return false
        }

        if isRevoked {
            return false
        }

        return hasValidStoredKey
    }

    static var isRevoked: Bool {
        isRevokedOverride ?? (cachedRevoked == true)
    }

    static var storedLicenseID: String? {
        storedRecord?.licenseID
    }

    static var registeredLine: String? {
        if isRevoked || AppLock.isLocked {
            return nil
        }

        if hasValidStoredKey, let name = storedName, !name.isEmpty {
            return "Registered to: \(name)"
        }

        return nil
    }

    static var storedName: String? {
        storedRecord?.name
    }

    static func hasValidStoredLicense() -> Bool {
        guard let record = readRecord() else {
            return false
        }

        return LicenseKey.isValid(name: record.name, email: record.email, key: record.key)
    }

    static func register(name: String, email: String, key: String) throws {
        try ensureNotAppLocked()

        let trimmedName = LicenseKey.canonicalName(name)
        let trimmedEmail = LicenseKey.canonicalEmail(email)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty, !trimmedKey.isEmpty else {
            throw RegistrationError.missingFields
        }

        guard LicenseKey.isValid(name: trimmedName, email: trimmedEmail, key: trimmedKey) else {
            throw RegistrationError.invalidKey
        }

        let licenseID = LicenseKey.licenseID(from: trimmedKey) ?? LicenseKey.banToken(from: trimmedKey)

        if cachedRevoked == true {
            throw RegistrationError.revoked
        }

        let remote = LicenseRemoteCheck.refresh(
            token: licenseID,
            version: AppInfo.shortVersion,
            reason: "register"
        )

        if let remote, remote.banned {
            cachedRevoked = true
            throw RegistrationError.revoked
        }

        try write(
            Record(
                name: trimmedName,
                email: trimmedEmail,
                key: trimmedKey,
                licenseID: licenseID,
                cachedRevoked: false,
                lastSuccessfulRemoteCheck: remote == nil ? nil : Date()
            )
        )

        cachedRevoked = false
        lastSuccessfulRemoteCheck = remote == nil ? nil : Date()
        remoteCheckID += 1
        LicenseGuard.refreshSentinel(forUnlocked: true)
        NotificationCenter.default.post(name: .licenseDidChange, object: nil)
    }

    static func clear() {
        remoteCheckID += 1
        cachedRevoked = nil
        lastSuccessfulRemoteCheck = nil
        try? FileManager.default.removeItem(at: registrationFileURL)
        LicenseGuard.refreshSentinel(forUnlocked: false)
        NotificationCenter.default.post(name: .licenseDidChange, object: nil)
    }

    static func hydrateFromStorage() {
        _ = readRecord()
        if hasValidStoredKey {
            LicenseGuard.refreshSentinel(forUnlocked: !isRevoked)
        }
    }

    static func resetSessionState() {
        remoteCheckID += 1
        cachedRevoked = nil
        lastSuccessfulRemoteCheck = nil
        isRevokedOverride = nil
    }

    private static var periodicRefreshTimer: Timer?
    private static let remoteRefreshInterval: TimeInterval = 60 * 60 * 24

    static func startPeriodicRemoteRefreshIfNeeded() {
        refreshRemoteStatusIfStale()
        periodicRefreshTimer?.invalidate()
        periodicRefreshTimer = Timer.scheduledTimer(withTimeInterval: remoteRefreshInterval, repeats: true) { _ in
            refreshRemoteStatus()
        }
    }

    static func refreshRemoteStatusIfStale() {
        guard storedRecord != nil else {
            return
        }

        if let lastSuccessfulRemoteCheck,
           Date().timeIntervalSince(lastSuccessfulRemoteCheck) < remoteRefreshInterval {
            return
        }

        refreshRemoteStatus()
    }

    static func refreshRemoteStatus() {
        guard let record = storedRecord,
              LicenseKey.isValid(name: record.name, email: record.email, key: record.key) else {
            cachedRevoked = nil
            return
        }

        let checkID = remoteCheckID
        let token = record.licenseID

        DispatchQueue.global(qos: .utility).async {
            let remote = LicenseRemoteCheck.refresh(token: token, version: AppInfo.shortVersion, reason: "activation")

            DispatchQueue.main.async {
                guard checkID == remoteCheckID else {
                    return
                }

                guard hasValidStoredKey else {
                    cachedRevoked = nil
                    return
                }

                applyRemoteResult(remote, to: record)
                NotificationCenter.default.post(name: .licenseDidChange, object: nil)
            }
        }
    }

    static func runStartupIntegrityCheck() {
        guard let issue = LicenseGuard.runIntegrityChecks() else {
            return
        }

        LicenseGuard.reportIntegrityIssue(issue)
    }

    static func ensureCanAddCommandSet(existingCount: Int) throws {
        try ensureNotAppLocked()
        try ensureIntegrityAllowsAccess()

        guard !LicenseGuard.permits(.addCommandSet), existingCount >= 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanAddSession() throws {
        try ensureNotAppLocked()
        try ensureIntegrityAllowsAccess()

        guard !LicenseGuard.permits(.addSession) else {
            return
        }

        throw restrictionError
    }

    static func ensureCanSaveSessions(_ count: Int) throws {
        try ensureNotAppLocked()
        try ensureIntegrityAllowsAccess()

        guard !LicenseGuard.permits(.addSession), count > 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanImport(resultingCount: Int) throws {
        try ensureNotAppLocked()
        try ensureIntegrityAllowsAccess()

        guard !LicenseGuard.permits(.importSets), resultingCount > 1 else {
            return
        }

        throw restrictionError
    }

    static func ensureCanRun(commandSet: CommandSet) throws {
        try ensureNotAppLocked()
        try ensureIntegrityAllowsAccess()

        guard !LicenseGuard.permits(.run) else {
            return
        }

        let isFirstCommandSet = CommandStore.commandSets.first?.id == commandSet.id
        let hasParallelSessions = commandSet.executableSessions.count > 1

        guard isFirstCommandSet, !hasParallelSessions else {
            throw restrictionError
        }
    }

    private static var restrictionError: RegistrationError {
        if AppLock.isLocked {
            return .updateRequired
        }

        return isRevoked ? .revoked : .registrationRequired
    }

    private struct Record: Codable {
        var name: String
        var email: String
        var key: String
        var licenseID: String
        var cachedRevoked: Bool?
        var lastSuccessfulRemoteCheck: Date?
    }

    private static var hasValidStoredKey: Bool {
        hasValidStoredLicense()
    }

    private static var storedRecord: Record? {
        readRecord()
    }

    private static func readRecord() -> Record? {
        let url = registrationFileURL

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }

        guard let plaintext = try? decrypt(data) else {
            return nil
        }

        guard let record = try? JSONDecoder().decode(Record.self, from: plaintext) else {
            return nil
        }

        cachedRevoked = record.cachedRevoked
        lastSuccessfulRemoteCheck = record.lastSuccessfulRemoteCheck
        return record
    }

    private static func write(_ record: Record) throws {
        let url = registrationFileURL
        try AppStoragePaths.ensureDirectory(at: url.deletingLastPathComponent())
        let plaintext = try JSONEncoder().encode(record)
        try encrypt(plaintext).write(to: url, options: .atomic)
    }

    static func applyAutoBanFromServer() {
        cachedRevoked = true
        persistRemoteState(revoked: true, checkedAt: Date())
        LicenseGuard.refreshSentinel(forUnlocked: false)
        NotificationCenter.default.post(name: .licenseDidChange, object: nil)
    }

    private static func applyRemoteResult(_ remote: LicenseRemoteCheck.RemoteResult?, to record: Record) {
        guard let remote else {
            if cachedRevoked == true {
                return
            }

            return
        }

        if remote.banned {
            cachedRevoked = true
            persistRemoteState(revoked: true, checkedAt: Date())

            
            return
        }

        cachedRevoked = false
        lastSuccessfulRemoteCheck = Date()
        persistRemoteState(revoked: false, checkedAt: Date())
        LicenseGuard.refreshSentinel(forUnlocked: true)
    }

    private static func persistRemoteState(revoked: Bool, checkedAt: Date) {
        guard var record = readRecord() else {
            return
        }

        record.cachedRevoked = revoked
        record.lastSuccessfulRemoteCheck = checkedAt
        try? write(record)
    }

    private static func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try RegistrationKeychain.fileKey())

        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }

        return combined
    }

    private static func decrypt(_ data: Data) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: try RegistrationKeychain.fileKey())
    }

    private static func ensureNotAppLocked() throws {
        if AppLock.isLocked {
            throw RegistrationError.updateRequired
        }
    }

    private static func ensureIntegrityAllowsAccess() throws {
        if LicenseGuard.integrityIssueOverride != nil || LicenseGuard.runIntegrityChecks() != nil {
            throw restrictionError
        }
    }
}
