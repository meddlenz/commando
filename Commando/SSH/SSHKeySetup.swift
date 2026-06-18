//
//  SSHKeySetup.swift
//  Commando
//

import Foundation

enum SSHKeySetup {

    enum SetupError: LocalizedError {
        case keyGenerationFailed(String)
        case keyInstallFailed(String)

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed(let message):
                return "Could not create SSH key: \(message)"
            case .keyInstallFailed(let message):
                return "Could not install SSH key on server: \(message)"
            }
        }
    }

    static var privateKeyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/id_ed25519")
    }

    static var publicKeyURL: URL {
        privateKeyURL.appendingPathExtension("pub")
    }

    static func hasLocalKey() -> Bool {
        FileManager.default.fileExists(atPath: publicKeyURL.path)
    }

    @discardableResult
    static func ensureLocalKeyExists() throws -> URL {
        if FileManager.default.fileExists(atPath: publicKeyURL.path) {
            return publicKeyURL
        }

        let sshDirectory = privateKeyURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: sshDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-t", "ed25519",
            "-f", privateKeyURL.path,
            "-N", "",
            "-C", "commando",
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SetupError.keyGenerationFailed(message ?? "Unknown error")
        }

        return publicKeyURL
    }

    static func installKey(on connection: SSHConnection, password: String) throws {
        let publicKeyURL = try ensureLocalKeyExists()
        let publicKey = try String(contentsOf: publicKeyURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !publicKey.isEmpty else {
            throw SetupError.keyInstallFailed("Public key file is empty.")
        }

        let escapedKey = publicKey.replacingOccurrences(of: "'", with: "'\\''")
        let remoteScript = """
        mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
        touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
        grep -qxF '\(escapedKey)' ~/.ssh/authorized_keys || echo '\(escapedKey)' >> ~/.ssh/authorized_keys
        """

        let sshCommand = SSHShellCommand.buildForPasswordAuth(
            connection: connection,
            remoteScript: remoteScript
        )

        do {
            _ = try SSHShellCommand.runWithPassword(sshCommand, password: password)
        } catch {
            throw SetupError.keyInstallFailed(error.localizedDescription)
        }
    }
}
