//
//  CommandSetDocument.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum CommandSetDocument {
    static let currentVersion = 1

    enum DocumentError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "This file was saved with a newer version of Commando (\(version)). Update Commando to import it."
            }
        }
    }

    struct Payload: Equatable {
        var version: Int
        var commandSets: [CommandSet]
    }

    static func encode(_ commandSets: [CommandSet]) throws -> Data {
        let encoder = JSONEncoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(FilePayload(version: currentVersion, commandSets: commandSets))
    }

    static func decode(_ data: Data) throws -> [CommandSet] {
        try decodePayload(data).commandSets
    }

    static func decodePayload(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()

        if let file = try? decoder.decode(FilePayload.self, from: data) {
            guard file.version <= currentVersion else {
                throw DocumentError.unsupportedVersion(file.version)
            }

            return Payload(version: file.version, commandSets: file.commandSets)
        }


        if let commandSets = try? decoder.decode([CommandSet].self, from: data) {
            return Payload(version: 1, commandSets: commandSets)
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Command set file is not valid JSON.")
        )
    }

    static func decodeStoredData(_ data: Data) throws -> [CommandSet] {
        if let decrypted = try? SecureDataStore.decrypt(data) {
            return try decode(decrypted)
        }

        return try decode(data)
    }

    static func merge(_ existing: [CommandSet], with imported: [CommandSet]) -> [CommandSet] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var order = existing.map(\.id)

        for commandSet in imported {
            if byID[commandSet.id] == nil {
                order.append(commandSet.id)
            }

            byID[commandSet.id] = commandSet
        }

        return order.compactMap { byID[$0] }
    }
}

private struct FilePayload: Codable {
    var version: Int
    var commandSets: [CommandSet]
}
