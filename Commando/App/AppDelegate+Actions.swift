//
//  AppDelegate+Actions.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa

extension AppDelegate {

    @objc func runCommandSet(_ sender: NSMenuItem) {
        let commandSets = UserDefaults.standard.commandSets
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
        SettingsWindowController.show()
    }

    @objc func openPreferences() {
        PreferencesWindowController.show()
    }

    @objc func openAbout() {
        AboutWindowController.show()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Unable to run command"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
