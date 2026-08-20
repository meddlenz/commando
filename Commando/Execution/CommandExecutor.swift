//
//  CommandExecutor.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum CommandExecutor {
    enum ExecutionError: LocalizedError {
        case invalidServerDetails
        case noSteps
        case terminalLaunchFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidServerDetails:
                return "Server must be username@host or username@host:port (without the ssh prefix)."
            case .noSteps:
                return "This command has no steps to run."
            case .terminalLaunchFailed(let message):
                return message
            }
        }
    }

    static func run(_ commandSet: CommandSet) throws {
        try LicenseStatus.ensureCanRun(commandSet: commandSet)

        try open(
            commands: try terminalCommands(for: commandSet),
            commandSetName: commandSet.name,
            sessionNames: commandSet.executableSessions.map(\.name)
        )
    }

    static func terminalCommand(for commandSet: CommandSet) throws -> String {
        guard let command = try terminalCommands(for: commandSet).first else {
            throw ExecutionError.noSteps
        }

        return command
    }

    static func terminalCommands(for commandSet: CommandSet) throws -> [String] {
        let serverDetails = SSHConnection.normaliseServerDetails(commandSet.serverDetails)
        let sessions = commandSet.executableSessions

        if let connection = SSHConnection.parse(from: serverDetails) {
            return sessions.map { session in
                let remoteSteps = remoteSteps(from: session.nonEmptySteps, for: connection)
                let remoteScript = SSHShellCommand.remoteScript(from: remoteSteps, keepSessionOpen: true)

                return buildSSHExecution(
                    connection: connection,
                    remoteScript: remoteScript,
                    interactive: true
                )
            }

        } else if !serverDetails.isEmpty {
            throw ExecutionError.invalidServerDetails

        } else if sessions.isEmpty {
            throw ExecutionError.noSteps
        } else {
            return sessions.map { $0.nonEmptySteps.joined(separator: "\n") }
        }
    }

    private static func remoteSteps(from steps: [String], for connection: SSHConnection) -> [String] {
        steps.compactMap { step in
            if let parsed = SSHStepParser.parseBareSSHCommand(step),
               parsed.username == connection.username,
               parsed.host == connection.host,
               parsed.port == connection.port,
               SSHStepParser.remoteCommand(from: step) == nil {
                return nil
            }
            
            return step
        }
    }

    private static func buildSSHExecution(
        connection: SSHConnection,
        remoteScript: String?,
        interactive: Bool
    ) -> String {
        SSHShellCommand.build(
            connection: connection,
            remoteScript: remoteScript,
            interactive: interactive,
            identityFile: SSHKeySetup.hasLocalKey() ? SSHKeySetup.privateKeyURL : nil
        )
    }

    private static func open(commands: [String], commandSetName: String, sessionNames: [String]) throws {
        let appPath = TerminalAppSettings.selectedAppPath

        do {
            try TerminalLauncher.open(
                commands: commands,
                commandSetName: commandSetName,
                sessionNames: sessionNames,
                appPath: appPath
            )
        } catch {
            throw ExecutionError.terminalLaunchFailed(error.localizedDescription)
        }
    }
}
