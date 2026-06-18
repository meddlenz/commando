//
//  CommandStore.swift
//  Commando
//

import Foundation

private let commandSetsKey = "commandSets"
private let legacyServerCommandsKey = "serverCommandsV2"

extension UserDefaults {

    var commandSets: [CommandSet] {
        get {
            if let data = data(forKey: commandSetsKey),
               let commandSets = try? JSONDecoder().decode([CommandSet].self, from: data) {
                return commandSets
            }
            return migrateLegacyServerCommands()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: commandSetsKey)
            NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
        }
    }

    private func migrateLegacyServerCommands() -> [CommandSet] {
        guard let data = data(forKey: legacyServerCommandsKey),
              let legacyCommands = try? JSONDecoder().decode([LegacyServerCommand].self, from: data),
              !legacyCommands.isEmpty else {
            return []
        }

        let migrated = legacyCommands.map { legacy in
            CommandSet(
                name: legacy.name.isEmpty ? legacy.serverDetails : legacy.name,
                serverDetails: legacy.serverDetails,
                steps: legacy.steps.isEmpty ? [""] : legacy.steps
            )
        }

        commandSets = migrated
        return migrated
    }
}

private struct LegacyServerCommand: Codable {
    var name: String
    var serverDetails: String
    var steps: [String]
}
