//
//  LaunchAtLoginSettings.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import CoreServices
import Foundation
import ServiceManagement

enum LaunchAtLoginSettings {

    private static let enabledKey = "launchAtLogin"

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return isRegisteredLegacy()
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

        } else {
            try setEnabledLegacy(enabled)
        }

        UserDefaults.standard.set(enabled, forKey: enabledKey)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @available(macOS, deprecated: 13.0)
    private static func isRegisteredLegacy() -> Bool {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue(),
              let appURL = Bundle.main.bundleURL as CFURL? else {
            return UserDefaults.standard.bool(forKey: enabledKey)
        }

        let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
       
        for item in items {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
               itemURL == appURL as URL {
                return true
            }
        }
        
        return false
    }

    @available(macOS, deprecated: 13.0)
    private static func setEnabledLegacy(_ enabled: Bool) throws {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue(),
              let appURL = Bundle.main.bundleURL as CFURL? else {
            throw LaunchAtLoginError.unavailable
        }

        if enabled {
            let item = LSSharedFileListInsertItemURL(
                loginItems,
                kLSSharedFileListItemBeforeFirst.takeUnretainedValue(),
                nil,
                nil,
                appURL,
                nil,

                nil
            )

            if item == nil {
                throw LaunchAtLoginError.registrationFailed
            }
        } else {
            let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
            
            for item in items {
                if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
                   itemURL == appURL as URL {
                    LSSharedFileListItemRemove(loginItems, item)
                }
            }
        }
    }

    enum LaunchAtLoginError: LocalizedError {
        case unavailable
        case registrationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Launch at login is not available on this Mac."
            case .registrationFailed:
                return "Could not add Commando to login items."
            }
        }
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("preferencesDidChange")
    static let showPreferences = Notification.Name("showPreferences")
}
