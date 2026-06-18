//
//  DockIconSettings.swift
//  Commando
//

import AppKit
import Foundation

enum DockIconSettings {

    private static let hiddenKey = "hideDockIcon"

    /// When `true`, the app hides its Dock icon (menu bar only).
    static var isHidden: Bool {
        UserDefaults.standard.bool(forKey: hiddenKey)
    }

    static func setHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: hiddenKey)
        applyPolicy(hidden: hidden)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    static func applyPolicy() {
        applyPolicy(hidden: isHidden)
    }

    private static func applyPolicy(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}
