//
//  SSHShellCommand.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum SSHShellCommand {

    static func build(
        connection: SSHConnection,
        remoteScript: String? = nil,
        interactive: Bool = false,
        identityFile: URL? = nil
    ) -> String {
        buildSSHInvocation(
            connection: connection,
             remoteScript: remoteScript,
            interactive: interactive,
            identityFile: identityFile,
            passwordAuth: false,
            strictHostKeyChecking: "accept-new"
        )
    }

    static func buildForPasswordAuth(
        connection: SSHConnection,
        remoteScript: String? = nil,
        interactive: Bool = false
    ) -> String {
        // TODO: Add password auth
        buildSSHInvocation(
            connection: connection,
            remoteScript: remoteScript,
            interactive: interactive, 
            identityFile: nil,
            passwordAuth: true,
            strictHostKeyChecking: "ask"
        )
    }

    static func remoteScript(from steps: [String], keepSessionOpen: Bool) -> String? {
        guard !steps.isEmpty else {
            return keepSessionOpen ? "exec bash -i </dev/tty" : nil
        }

        var lines = ["set -e"]
        lines.append(contentsOf: steps)

        if keepSessionOpen {
            lines.append("exec bash -i </dev/tty")
        }


        return lines.joined(separator: "\n")
    }

    private static func buildSSHInvocation(
        connection: SSHConnection,
        remoteScript: String?,
        interactive: Bool,
        identityFile: URL?,
        passwordAuth: Bool,
        strictHostKeyChecking: String
    ) -> String {
        var sshLine = "ssh -o StrictHostKeyChecking=\(strictHostKeyChecking)"

        if passwordAuth {
             sshLine += " -o PreferredAuthentications=password,keyboard-interactive"
            sshLine += " -o PubkeyAuthentication=no"
        } else if let identityFile {
            sshLine += " -o IdentitiesOnly=yes -i \(shellQuote(identityFile.path))"
        }

        if interactive {
            sshLine += " -t"

        }

        if let port = connection.port {
            sshLine += " -p \(port)"
        }

        sshLine += " \(shellQuote("\(connection.username)@\(connection.host)"))"

        guard let remoteScript, !remoteScript.isEmpty else {
            return sshLine
        }

        // Run from a temp script file so `ssh -t` keeps a PTY and `exec bash -i` works
        let encoded = Data(remoteScript.utf8).base64EncodedString()
        let remoteCommand = "f=$(mktemp /tmp/commandrunner.XXXXXX.sh) && echo \(encoded) | base64 -d > \"$f\" && bash \"$f\"; e=$?; rm -f \"$f\"; exit $e"

        return "\(sshLine) \(shellQuote(remoteCommand))"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
