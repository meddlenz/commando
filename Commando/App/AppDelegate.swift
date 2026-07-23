//
//  AppDelegate.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var playMenuIcon: NSImage? = Self.makePlayMenuIcon()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Commando menu bar item")

        ExampleCommandSet.installIfNeeded()
        applyDockIconPreference()
        UpdateChecker.checkForUpdateIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(commandSetsDidChange(_:)),
            name: .commandSetsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .preferencesDidChange,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.show()
        return true
    }

    @objc private func commandSetsDidChange(_ notification: Notification) {
        constructMenu()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        applyDockIconPreference()
    }

    private func applyDockIconPreference() {
        DockIconSettings.applyPolicy()
        configureStatusItem()
    }
}
