//  Jordan Trbuhovic 2026
//  AppStoragePaths.swift
//  Commando
//

import Foundation

enum AppStoragePaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Commando", isDirectory: true)
    }

    static var terminalRunsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("terminal-runs", isDirectory: true)
    }

    static var sshDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("ssh", isDirectory: true)
    }

    static var privateKeyURL: URL {
        sshDirectory.appendingPathComponent("commando_ed25519")
    }

    static var publicKeyURL: URL {
        privateKeyURL.appendingPathExtension("pub")
    }

    static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }
}
