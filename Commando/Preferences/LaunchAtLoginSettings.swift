//
//  LaunchAtLoginSettings.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation
import ServiceManagement

enum LaunchAtLoginSettings {
    private static let enabledKey = "launchAtLogin"
    private static let loginItemIdentifier = "com.manticoresw.commando.loginitem"

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return isLoginItemRegistered()
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else {
            try setLoginItemEnabled(enabled)
        }

        UserDefaults.standard.set(enabled, forKey: enabledKey)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private static func isLoginItemRegistered() -> Bool {
        guard let jobs = LaunchAtLoginJobLookup.jobs else {
            return UserDefaults.standard.bool(forKey: enabledKey)
        }

        guard let job = jobs.first(where: { ($0["Label"] as? String) == loginItemIdentifier }) else {
            return false
        }

        return (job["OnDemand"] as? Bool) == false
    }

    private static func setLoginItemEnabled(_ enabled: Bool) throws {
        guard SMLoginItemSetEnabled(loginItemIdentifier as CFString, enabled) else {
            throw LaunchAtLoginError.registrationFailed
        }
    }

    enum LaunchAtLoginError: LocalizedError {
        case registrationFailed

        var errorDescription: String? {
            switch self {
            case .registrationFailed:
                return "Could not add Commando to login items."
            }
        }
    }
}

private enum LaunchAtLoginJobLookup {
    static var jobs: [[String: AnyObject]]? {
        SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: AnyObject]]
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("preferencesDidChange")
    static let showPreferences = Notification.Name("showPreferences")
}
