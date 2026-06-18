//
//  CommandSet.swift
//  Commando
//

import Foundation

extension Notification.Name {
    static let commandSetsDidChange = Notification.Name("commandSetsDidChange")
}

struct CommandSet: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var serverDetails: String
    var steps: [String]
    var keepSessionOpen: Bool

    init(
        id: UUID = UUID(),
        name: String,
        serverDetails: String = "",
        steps: [String] = [""],
        keepSessionOpen: Bool = true
    ) {
        self.id = id
        self.name = name
        self.serverDetails = serverDetails
        self.steps = steps.isEmpty ? [""] : steps
        self.keepSessionOpen = keepSessionOpen
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case serverDetails
        case steps
        case commands
        case keepSessionOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Command"
        serverDetails = try container.decodeIfPresent(String.self, forKey: .serverDetails) ?? ""
        keepSessionOpen = try container.decodeIfPresent(Bool.self, forKey: .keepSessionOpen) ?? true

        if let stringSteps = try? container.decode([String].self, forKey: .steps), !stringSteps.isEmpty {
            steps = stringSteps
        } else if let structuredSteps = try? container.decode([StoredCommandStep].self, forKey: .steps), !structuredSteps.isEmpty {
            steps = structuredSteps.compactMap(\.commandText)
            if steps.isEmpty {
                steps = [""]
            }
        } else if let legacyCommands = try container.decodeIfPresent([String].self, forKey: .commands), !legacyCommands.isEmpty {
            steps = legacyCommands
        } else {
            steps = [""]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverDetails, forKey: .serverDetails)
        try container.encode(steps, forKey: .steps)
        try container.encode(keepSessionOpen, forKey: .keepSessionOpen)
    }

    var nonEmptySteps: [String] {
        steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var stepsSummary: String {
        let commands = nonEmptySteps
        guard !commands.isEmpty else { return "No steps" }
        if commands.count == 1 { return commands[0] }
        return "\(commands.count) steps"
    }

    var isRemote: Bool {
        !serverDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var menuSubtitle: String {
        if isRemote {
            return serverDetails
        }
        return stepsSummary
    }
}

/// Decodes the short-lived structured step format (including removed delay steps).
private struct StoredCommandStep: Codable {
    var kind: String?
    var text: String

    var commandText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if kind == "delay" {
            guard let seconds = Double(trimmed), seconds > 0 else { return nil }
            if seconds.rounded() == seconds {
                return "sleep \(Int(seconds))"
            }
            return "sleep \(seconds)"
        }
        return trimmed
    }
}
