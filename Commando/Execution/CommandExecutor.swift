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

    static func run(_ commandSet: CommandSet, password: String? = nil) throws {
        try open(
            command: try terminalCommand(for: commandSet, password: password),
            commandSetName: commandSet.name
        )
    }

    static func terminalCommand(for commandSet: CommandSet, password: String? = nil) throws -> String {
        let savedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let serverDetails = SSHConnection.normaliseServerDetails(commandSet.serverDetails)

        if let connection = SSHConnection.parse(from: serverDetails) {
            let remoteSteps = remoteSteps(from: commandSet.nonEmptySteps, for: connection)
            let remoteScript = SSHShellCommand.remoteScript(from: remoteSteps, keepSessionOpen: true)
            
            return buildSSHExecution(
                connection: connection,
                remoteScript: remoteScript,
                password: savedPassword,
                interactive: true
            )

        } else if !serverDetails.isEmpty {
            throw ExecutionError.invalidServerDetails

        } else if let savedPassword,
                  commandSet.nonEmptySteps.count == 1,
                  let connection = SSHStepParser.parseBareSSHCommand(commandSet.nonEmptySteps[0]) {
            let remoteCommand = SSHStepParser.remoteCommand(from: commandSet.nonEmptySteps[0])

            return buildSSHExecution(
                connection: connection,
                remoteScript: remoteCommand,
                password: savedPassword,
                interactive: remoteCommand == nil
            )

        } else if commandSet.nonEmptySteps.isEmpty {
            throw ExecutionError.noSteps
        } else {
            return commandSet.nonEmptySteps.joined(separator: "\n")
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
        password: String?,
        interactive: Bool
    ) -> String {
        let sshCommand: String

        if let password {
            sshCommand = SSHShellCommand.buildForPasswordAuth(
                connection: connection,
                remoteScript: remoteScript,
                interactive: interactive
            )

            return SSHShellCommand.wrapForTerminal(sshCommand, password: password)
        }

        sshCommand = SSHShellCommand.build(
            connection: connection,
            remoteScript: remoteScript,
            interactive: interactive,
            identityFile: SSHKeySetup.hasLocalKey() ? SSHKeySetup.privateKeyURL : nil
        )

        return sshCommand
    }

    private static func open(command: String, commandSetName: String) throws {
        let appPath = TerminalAppSettings.selectedAppPath
        
        do {
            try TerminalLauncher.open(command: command, commandSetName: commandSetName, appPath: appPath)
        } catch {
            throw ExecutionError.terminalLaunchFailed(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
