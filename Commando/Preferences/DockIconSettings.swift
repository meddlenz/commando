//
//  DockIconSettings.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import Foundation

enum DockIconSettings {

    private static let hiddenKey = "hideDockIcon"

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
