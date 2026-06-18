//
//  SSHConnection.swift
//  Commando
//

import Foundation

struct SSHConnection {
    let username: String
    let host: String
    let port: Int?

    static func normalizeServerDetails(_ serverDetails: String) -> String {
        var trimmed = serverDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ssh ") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func parse(from serverDetails: String) -> SSHConnection? {
        let trimmed = normalizeServerDetails(serverDetails)
        guard !trimmed.isEmpty else { return nil }

        let hostPart: String
        let username: String

        guard let atIndex = trimmed.lastIndex(of: "@") else { return nil }
        username = String(trimmed[..<atIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        hostPart = String(trimmed[trimmed.index(after: atIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !hostPart.isEmpty, !username.contains(" ") else { return nil }

        if let colonIndex = hostPart.lastIndex(of: ":"),
           hostPart[hostPart.index(after: colonIndex)...].allSatisfy(\.isNumber) {
            let host = String(hostPart[..<colonIndex])
            let portString = String(hostPart[hostPart.index(after: colonIndex)...])
            guard let port = Int(portString), !host.isEmpty else { return nil }
            return SSHConnection(username: username, host: host, port: port)
        }

        return SSHConnection(username: username, host: hostPart, port: nil)
    }
}
