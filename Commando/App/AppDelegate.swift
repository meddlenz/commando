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
    private var didShowRevocationAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Commando menu bar item")

        CommandStore.start()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(licenseDidChange(_:)),
            name: .licenseDidChange,
            object: nil
        )

        LicenseStatus.refreshBanStatus()
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

    @objc private func licenseDidChange(_ notification: Notification) {
        constructMenu()
        presentRevocationAlertIfNeeded()
    }

    private func presentRevocationAlertIfNeeded() {
        guard LicenseStatus.isRevoked else {
            didShowRevocationAlert = false
            return

        }

        guard !didShowRevocationAlert else {
            return
        }

        didShowRevocationAlert = true

        let alert = NSAlert()
        
        alert.messageText = "License revoked"
        alert.informativeText = LicenseStatus.RegistrationError.revoked.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Ok")
        alert.runModal()
    }

    private func applyDockIconPreference() {
        DockIconSettings.applyPolicy()
        configureStatusItem()
    }
}
