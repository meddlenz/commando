//  
//  AppStoragePaths.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum AppStoragePaths {
    static let commandSetsFileName = "command-sets.json"
    static let registrationFileName = "registration.dat"
    static let iCloudContainerIdentifier = "iCloud.com.manticoresw.commando"

    static var applicationSupportDirectory: URL {
         let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Commando", isDirectory: true)
    }

    static var localCommandSetsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent(commandSetsFileName)
    }

    static var registrationFileURL: URL {
        applicationSupportDirectory.appendingPathComponent(registrationFileName)
    }

    static var terminalRunsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("terminal-runs", isDirectory: true)
    }

    static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
