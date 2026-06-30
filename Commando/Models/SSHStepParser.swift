//
//  SSHStepParser.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum SSHStepParser {

    /// Parses `ssh [-p PORT] user@host` from a local step command.
    static func parseBareSSHCommand(_ command: String) -> SSHConnection? {
        var tokens = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard tokens.first == "ssh" else {
            return nil
        }

        tokens.removeFirst()

        var port: Int?

        while !tokens.isEmpty {
            let token = tokens[0]

            if token == "-p", tokens.count >= 2, let parsedPort = Int(tokens[1]) {
                port = parsedPort
                tokens.removeFirst(2)

                continue
            }

            if token.hasPrefix("-") {
                let flag = token == "-o" ? token : String(token.prefix(while: { $0 != "=" }))
                let flagsWithValue: Set<String> = ["-p", "-i", "-o", "-l", "-F", "-J", "-b", "-c", "-E", "-e", "-I", "-L", "-R", "-S", "-W", "-w"]
                
                if flagsWithValue.contains(flag), tokens.count >= 2, !tokens[1].hasPrefix("-") {
                    tokens.removeFirst(2)
                } else {
                    tokens.removeFirst()
                }

                continue
            }

            break
        }

        guard let target = tokens.first,
              let connection = SSHConnection.parse(from: target) else {

            return nil
        }

        if let port {
            return SSHConnection(username: connection.username, host: connection.host, port: port)
        }

        return connection
    }

    /// Returns any command run on the remote host after the ssh target
    static func remoteCommand(from command: String) -> String? {
        var tokens = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard tokens.first == "ssh" else {
            return nil
        }

        tokens.removeFirst()

        while !tokens.isEmpty {
            let token = tokens[0]

            if token == "-p", tokens.count >= 2 {
                tokens.removeFirst(2)
                continue
            }


            if token.hasPrefix("-") {
                let flag = token == "-o" ? token : String(token.prefix(while: { $0 != "=" }))
                
                let flagsWithValue: Set<String> = ["-p", "-i", "-o", "-l", "-F", "-J", "-b", "-c", "-E", "-e", "-I", "-L", "-R", "-S", "-W", "-w"]
                
                if flagsWithValue.contains(flag), tokens.count >= 2, !tokens[1].hasPrefix("-") {
                    tokens.removeFirst(2)
                } else {
                    tokens.removeFirst()
                }

                continue
            }
            
            break
        }

        guard !tokens.isEmpty else {
            return nil
        }

        tokens.removeFirst()
        guard !tokens.isEmpty else {
            return nil
        }

        return tokens.joined(separator: " ")
    }

    static func isBareSSHStep(_ command: String) -> Bool {
        parseBareSSHCommand(command) != nil
    }
}
