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
        applyPolicy(hidden: isHidden && !hasOpenAppWindows)
    }

    static func showDockForOpenWindow() {
        guard isHidden else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func refreshAfterWindowClosed() {
        DispatchQueue.main.async {
            applyPolicy()
            if hasOpenAppWindows {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private static var hasOpenAppWindows: Bool {
        NSApp.windows.contains(where: isOpenAppWindow)
    }

    private static func isOpenAppWindow(_ window: NSWindow) -> Bool {
        let mask = window.styleMask
        guard mask.contains(.titled) else { return false }
        guard mask.contains(.closable) || mask.contains(.miniaturizable) else { return false }
        return window.isVisible || window.isMiniaturized
    }

    private static func applyPolicy(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}
