//
//  LicenseGuard.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import CryptoKit
import Foundation
import Security

enum LicenseGuard {
    enum Feature {
        case run
        case importSets
        case addCommandSet
        case addSession
        case register
        case general
    }

    enum IntegrityIssue: Equatable {
        case codesignInvalid
        case unlockMismatch
        case tamperedSentinel
    }

    static var integrityIssueOverride: IntegrityIssue?
    static var skipIntegrityChecks = false

    private static let sentinelFileName = "license-sentinel.dat"

    static func permits(_ feature: Feature) -> Bool {
        if AppLock.isLocked {
            return false
        }

        if integrityIssueOverride != nil {
            return false
        }

        if !skipIntegrityChecks, let issue = runIntegrityChecks() {
            reportIntegrityIssue(issue)
            return false
        }

        switch feature {
        case .register:
            return !LicenseStatus.isRevoked
        case .general:
            return true
        default:
            return LicenseStatus.isUnlocked
        }
    }

    static func runIntegrityChecks() -> IntegrityIssue? {
        if skipIntegrityChecks {
            return nil
        }

        if !verifyCodesignIntegrity() {
            return .codesignInvalid
        }

        let cryptographicallyUnlocked = LicenseStatus.hasValidStoredLicense()
        let sentinelMatches = sentinelMatchesUnlockState(cryptographicallyUnlocked)

        if cryptographicallyUnlocked != LicenseStatus.isUnlockedPublicState {
            return .unlockMismatch
        }

        if !sentinelMatches {
            return .tamperedSentinel
        }

        return nil
    }

    static func refreshSentinel(forUnlocked unlocked: Bool) {
        let token = sentinelToken(unlocked: unlocked)
        let url = sentinelFileURL

        do {
            try AppStoragePaths.ensureDirectory(at: url.deletingLastPathComponent())
            try token.write(to: url, options: .atomic)
        } catch {
            if !unlocked {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func verifyCodesignIntegrity() -> Bool {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }

        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    static func reportIntegrityIssue(_ issue: IntegrityIssue) {
        if let token = LicenseStatus.storedLicenseID {
            LicenseRemoteCheck.reportTamper(
                token: token,
                detail: issueDetail(issue),
                version: AppInfo.shortVersion
            )
        }
    }

    private static func issueDetail(_ issue: IntegrityIssue) -> String {
        switch issue {
        case .codesignInvalid:
            return "codesign_invalid"
        case .unlockMismatch:
            return "unlock_mismatch"
        case .tamperedSentinel:
            return "sentinel_mismatch"
        }
    }

    private static func sentinelMatchesUnlockState(_ unlocked: Bool) -> Bool {
        let expected = sentinelToken(unlocked: unlocked)
        let url = sentinelFileURL

        guard let data = try? Data(contentsOf: url) else {
            return !unlocked
        }

        return data == expected
    }

    private static func sentinelToken(unlocked: Bool) -> Data {
        let marker = unlocked ? "unlocked" : "locked"
        let material = Data("commando.sentinel.v1".utf8) + Data(marker.utf8)
        return Data(SHA256.hash(data: material))
    }

    private static var sentinelFileURL: URL {
        AppStoragePaths.applicationSupportDirectory.appendingPathComponent(sentinelFileName)
    }
}
