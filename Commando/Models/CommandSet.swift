//
//  CommandSet.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

extension Notification.Name {
    static let commandSetsDidChange = Notification.Name("commandSetsDidChange")
}

struct CommandSession: Equatable, Codable {
    var name: String
    var steps: [String]

    init(name: String = "", steps: [String] = [""]) {
        self.name = name
        self.steps = steps.isEmpty ? [""] : steps
    }
    

    enum CodingKeys: String, CodingKey {
        case name
        case steps
    }

    init(from decoder: Decoder) throws {
        if let steps = try? decoder.singleValueContainer().decode([String].self) {
            self.init(steps: steps)

            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            steps: try container.decodeIfPresent([String].self, forKey: .steps) ?? [""]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(steps, forKey: .steps)
    }

    var nonEmptySteps: [String] {
        steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CommandSet: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var serverDetails: String
    var sessions: [CommandSession]
    var keepSessionOpen: Bool

    init(
        id: UUID = UUID(),
        name: String,
        serverDetails: String = "",
        steps: [String] = [""],
        sessions: [CommandSession]? = nil,
        keepSessionOpen: Bool = true
    ) {
        self.id = id
        self.name = name
        self.serverDetails = serverDetails
        self.sessions = Self.normalisedSessions(sessions ?? [CommandSession(steps: steps)])
        self.keepSessionOpen = keepSessionOpen
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case serverDetails
        case steps
        case sessions
        case commands
        case keepSessionOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Command"
        serverDetails = try container.decodeIfPresent(String.self, forKey: .serverDetails) ?? ""
        keepSessionOpen = try container.decodeIfPresent(Bool.self, forKey: .keepSessionOpen) ?? true

        if let decodedSessions = try? container.decode([CommandSession].self, forKey: .sessions), !decodedSessions.isEmpty {
            sessions = Self.normalisedSessions(decodedSessions)
        } else {
            sessions = [CommandSession(steps: Self.decodeSteps(from: container))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverDetails, forKey: .serverDetails)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(steps, forKey: .steps)
        try container.encode(keepSessionOpen, forKey: .keepSessionOpen)
    }

    var steps: [String] {
        sessions.first?.steps ?? [""]
    }

    var nonEmptySteps: [String] {
        nonEmptySessions.flatMap { $0 }
    }

    var nonEmptySessions: [[String]] {
        executableSessions.map(\.nonEmptySteps).filter { !$0.isEmpty }
    }

    var executableSessions: [CommandSession] {
        let sessions = self.sessions.compactMap { session -> CommandSession? in
            let steps = session.nonEmptySteps

            guard !steps.isEmpty else {
                return nil }

            return CommandSession(name: session.name, steps: steps)
        }

        if !sessions.isEmpty {
            return sessions
        }

        return isRemote ? [CommandSession(name: self.sessions.first?.name ?? "", steps: [])] : []
    }

    var stepsSummary: String {
        let sessions = nonEmptySessions


        if sessions.count > 1 {
            return "\(sessions.count) sessions"
        }

        let commands = sessions.first ?? []

        guard !commands.isEmpty else {
            return "No steps"
            }

        if commands.count == 1 {
            return commands[0]
        }

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

    private static func normalisedSessions(_ sessions: [CommandSession]) -> [CommandSession] {
        let normalised = sessions.map { CommandSession(name: $0.name, steps: $0.steps.isEmpty ? [""] : $0.steps) }
        
        return normalised.isEmpty ? [CommandSession()] : normalised
    }

    private static func decodeSteps(from container: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let stringSteps = try? container.decode([String].self, forKey: .steps), !stringSteps.isEmpty {
            return stringSteps
        }

        if let structuredSteps = try? container.decode([StoredCommandStep].self, forKey: .steps), !structuredSteps.isEmpty {
            let steps = structuredSteps.compactMap(\.commandText)
            
            return steps.isEmpty ? [""] : steps
        }

        if let legacyCommands = try? container.decode([String].self, forKey: .commands), !legacyCommands.isEmpty {
            return legacyCommands
        }

        return [""]
    }
}



private struct StoredCommandStep: Codable {
    var kind: String?
    var text: String

    var commandText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        
        if kind == "delay" {

            guard let seconds = Double(trimmed), seconds > 0 else {
                return nil
            }

            if seconds.rounded() == seconds {
                return "sleep \(Int(seconds))"
            }

            return "sleep \(seconds)"
        }

        return trimmed
    }
}
