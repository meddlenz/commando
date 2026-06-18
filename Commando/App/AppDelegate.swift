//
//  AppDelegate.swift
//  Commando
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var playMenuIcon: NSImage? = Self.makePlayMenuIcon()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Commando menu bar item")

        applyDockIconPreference()

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

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
