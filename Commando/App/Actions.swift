//
//  Actions.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa

extension AppDelegate {

    @objc func runCommandSet(_ sender: NSMenuItem) {
        let commandSets = CommandStore.commandSets
        guard commandSets.indices.contains(sender.tag) else {
            constructMenu()
            return
        }

        do {
            let commandSet = commandSets[sender.tag]
            try CommandExecutor.run(commandSet)
        } catch {
            presentError(error)
        }
    }

    @objc func showPreferences(_ sender: Any?) {
        openPreferences()
    }

    @objc func showAbout(_ sender: Any?) {
        openAbout()
    }

    @objc func showSettings(_ sender: Any?) {
        openCommandSets()
    }

    @objc func openCommandSets() {
        DockIconSettings.showDockForOpenWindow()
        SettingsWindowController.show()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openPreferences() {
        DockIconSettings.showDockForOpenWindow()
        PreferencesWindowController.show()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openAbout() {
        DockIconSettings.showDockForOpenWindow()
        AboutWindowController.show()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openRegistration() {
        DockIconSettings.showDockForOpenWindow()
        RegistrationWindowController.show()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openPurchase() {
        NSWorkspace.shared.open(AppInfo.purchaseURL)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Unable to run command"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Ok")
        alert.runModal()
    }
}

