//
//  SSHKeySetup.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Darwin
import Foundation

enum SSHKeySetup {
    enum SetupError: LocalizedError {
        case keyInstallFailed(String)

        var errorDescription: String? {
            switch self {
            case .keyInstallFailed(let message):
                return "Could not install SSH key on server: \(message)"
            }
        }
    }

    static var privateKeyURL: URL {
        realUserHomeDirectory
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("commando_ed25519")
    }

    static var publicKeyURL: URL {
        privateKeyURL.appendingPathExtension("pub")
    }

    static func hasLocalKey() -> Bool {
        FileManager.default.fileExists(atPath: publicKeyURL.path)
    }

    static func installKey(on connection: SSHConnection) throws {
        let remoteScript = """
        set -e
        umask 077
        mkdir -p ~/.ssh
        touch ~/.ssh/authorized_keys
        key=$(cat)
        grep -qxF "$key" ~/.ssh/authorized_keys || printf '%s\\n' "$key" >> ~/.ssh/authorized_keys
        """

        let sshCommand = SSHShellCommand.buildForPasswordAuth(
            connection: connection,
            remoteScript: remoteScript
        )
        let destination = "\(connection.username)@\(connection.host)"
        let keyPath = SSHShellCommand.shellQuote(privateKeyURL.path)
        let publicKeyPath = SSHShellCommand.shellQuote(publicKeyURL.path)
        let terminalCommand = """
        key_path=\(keyPath)
        public_key_path=\(publicKeyPath)
        mkdir -p "$(dirname "$key_path")"
        chmod 700 "$(dirname "$key_path")"
        if [ ! -f "$key_path" ]; then
          /usr/bin/ssh-keygen -t ed25519 -f "$key_path" -N '' -C commando
        fi
        if [ ! -f "$public_key_path" ]; then
          /usr/bin/ssh-keygen -y -f "$key_path" > "$public_key_path"
        fi
        chmod 600 "$key_path"
        chmod 644 "$public_key_path"
        /bin/cat "$public_key_path" | \(sshCommand)
        printf '\\nSSH key installed successfully on %s.\\n' \(SSHShellCommand.shellQuote(destination))
        """

        do {
            try TerminalLauncher.open(
                command: terminalCommand,
                commandSetName: "Set Up SSH Key",
                appPath: TerminalAppSettings.selectedAppPath
            )
        } catch {
            throw SetupError.keyInstallFailed(error.localizedDescription)
        }
    }

    private static var realUserHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
