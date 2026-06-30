//
//  SSHKeySetupPrompt.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit

enum SSHKeySetupPrompt {

    static func prompt(for connection: SSHConnection) -> String? {
        let alert = NSAlert()
        alert.messageText = "Set Up SSH Key"
        alert.informativeText = """
        Enter the server password and Commando will create an SSH key if needed, \
        and install it on \(connection.username)@\(connection.host). \
        After that, connections can be made without password prompting.
        """

        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Key")
        alert.addButton(withTitle: "Cancel")

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        
        passwordField.placeholderString = "Server password"
        alert.accessoryView = passwordField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return password.isEmpty ? nil : password
    }

    static func showSuccess(for connection: SSHConnection) {
        let alert = NSAlert()

        alert.messageText = "SSH Key Installed"
        alert.informativeText = """
        Your SSH key is now authorized on \(connection.username)@\(connection.host).
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showError(_ error: Error) {
        let alert = NSAlert()
        
        alert.messageText = "SSH Key Setup Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
