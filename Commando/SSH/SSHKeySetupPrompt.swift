//
//  SSHKeySetupPrompt.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit

enum SSHKeySetupPrompt {

    static func confirm(for connection: SSHConnection) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Set Up SSH Key"
        alert.informativeText = """
        Commando will open \(TerminalAppSettings.selectedAppName) and install an SSH key on \
        \(connection.username)@\(connection.host).

        Enter the server password in the terminal when prompted, and verify the \
        server fingerprint before continuing. SSH authenticates there, Commando does \
        not receive or store that password.
        """

        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
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
