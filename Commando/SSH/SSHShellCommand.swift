//
//  SSHShellCommand.swift
//  Commando
//

import Foundation

enum SSHShellCommand {

    static func build(
        connection: SSHConnection,
        remoteScript: String? = nil,
        interactive: Bool = false,
        identityFile: URL? = nil
    ) -> String {
        buildSSHInvocation(
            connection: connection,
            remoteScript: remoteScript,
            interactive: interactive,
            identityFile: identityFile,
            passwordAuth: false
        )
    }

    static func buildForPasswordAuth(
        connection: SSHConnection,
        remoteScript: String? = nil,
        interactive: Bool = false
    ) -> String {
        buildSSHInvocation(
            connection: connection,
            remoteScript: remoteScript,
            interactive: interactive,
            identityFile: nil,
            passwordAuth: true
        )
    }

    /// Each step becomes one line in a remote shell script so state (e.g. cd) persists.
    static func remoteScript(from steps: [String], keepSessionOpen: Bool) -> String? {
        guard !steps.isEmpty else {
            return keepSessionOpen ? "exec bash -i </dev/tty" : nil
        }

        var lines = ["set -e"]
        lines.append(contentsOf: steps)
        if keepSessionOpen {
            lines.append("exec bash -i </dev/tty")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildSSHInvocation(
        connection: SSHConnection,
        remoteScript: String?,
        interactive: Bool,
        identityFile: URL?,
        passwordAuth: Bool
    ) -> String {
        var sshLine = "ssh -o StrictHostKeyChecking=accept-new"

        if passwordAuth {
            sshLine += " -o PreferredAuthentications=password,keyboard-interactive"
            sshLine += " -o PubkeyAuthentication=no"
        } else if let identityFile {
            sshLine += " -o IdentitiesOnly=yes -i \(shellQuote(identityFile.path))"
        }

        if interactive {
            sshLine += " -t"
        }
        if let port = connection.port {
            sshLine += " -p \(port)"
        }

        sshLine += " \(shellQuote("\(connection.username)@\(connection.host)"))"

        guard let remoteScript, !remoteScript.isEmpty else {
            return sshLine
        }

        // Run from a temp script file (not stdin) so `ssh -t` keeps a PTY and `exec bash -i` works.
        let encoded = Data(remoteScript.utf8).base64EncodedString()
        let remoteCommand = "f=$(mktemp /tmp/commandrunner.XXXXXX.sh) && echo \(encoded) | base64 -d > \"$f\" && bash \"$f\"; e=$?; rm -f \"$f\"; exit $e"
        return "\(sshLine) \(shellQuote(remoteCommand))"
    }

    @discardableResult
    static func runWithPassword(_ command: String, password: String) throws -> Int32 {
        if let sshpass = sshpassPath() {
            return try runProcess(
                executable: sshpass,
                arguments: ["-e", "/bin/bash", "-s"],
                environment: ["SSHPASS": password],
                standardInput: command
            )
        }
        return try runWithExpect(command: command, password: password, interactive: command.contains(" -t "))
    }

    static func wrapForTerminal(_ command: String, password: String) -> String {
        if let sshpass = sshpassPath() {
            let passwordBase64 = Data(password.utf8).base64EncodedString()
            let commandBase64 = Data(command.utf8).base64EncodedString()
            return """
            export SSHPASS=$(echo '\(passwordBase64)' | base64 -d); \
            echo '\(commandBase64)' | base64 -d | \(shellQuote(sshpass)) -e /bin/bash -s; \
            STATUS=$?; unset SSHPASS; exit $STATUS
            """
        }
        return wrapWithExpectForTerminal(command: command, password: password, interactive: command.contains(" -t "))
    }

    private static func wrapWithExpectForTerminal(command: String, password: String, interactive: Bool) -> String {
        let passwordBase64 = Data(password.utf8).base64EncodedString()
        let commandBase64 = Data(command.utf8).base64EncodedString()
        let expectBody = expectScriptBody(interactive: interactive)

        return """
        export CR_PASS_B64='\(passwordBase64)'; \
        SCRIPT_FILE=$(mktemp -t commandrunner.XXXXXX.sh); \
        echo '\(commandBase64)' | base64 -d > "$SCRIPT_FILE"; chmod 700 "$SCRIPT_FILE"; \
        export SCRIPT_FILE; \
        EXPECT_FILE=$(mktemp -t commandrunner.XXXXXX.exp); \
        cat > "$EXPECT_FILE" << 'EXPECTEOF'
        \(expectBody)
        EXPECTEOF
        chmod 700 "$EXPECT_FILE"; \
        /usr/bin/expect -f "$EXPECT_FILE"; \
        STATUS=$?; rm -f "$EXPECT_FILE" "$SCRIPT_FILE"; unset CR_PASS_B64; exit $STATUS
        """
    }

    private static func expectScriptBody(interactive: Bool) -> String {
        var lines = [
            "#!/usr/bin/expect -f",
            "set timeout 120",
            "set password [exec /bin/sh -c \"echo $env(CR_PASS_B64) | base64 -d\"]",
            "set scriptFile $env(SCRIPT_FILE)",
            "spawn /bin/bash $scriptFile",
            "expect {",
            "    -re {(?i)(yes/no|continue connecting|fingerprint)} {",
            "        send \"yes\\r\"",
            "        exp_continue",
            "    }",
            "    -re {(?i)password:} {",
            "        send \"$password\\r\"",
            "        exp_continue",
            "    }",
            "}",
        ]

        if interactive {
            lines.append("interact")
        } else {
            lines += [
                "expect eof",
                "catch wait result",
                "exit [lindex $result 3]",
            ]
        }

        return lines.joined(separator: "\n")
    }

    private static func runWithExpect(command: String, password: String, interactive: Bool) throws -> Int32 {
        let passwordBase64 = Data(password.utf8).base64EncodedString()
        let commandURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("commandrunner-expect-\(UUID().uuidString).sh")
        let expectURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("commandrunner-expect-\(UUID().uuidString).exp")

        try command.write(to: commandURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: commandURL)
            try? FileManager.default.removeItem(at: expectURL)
        }

        let expectBody = expectScriptBody(interactive: interactive)
        try expectBody.write(to: expectURL, atomically: true, encoding: .utf8)

        var environment = ProcessInfo.processInfo.environment
        environment["CR_PASS_B64"] = passwordBase64
        environment["SCRIPT_FILE"] = commandURL.path

        return try runProcess(
            executable: "/usr/bin/expect",
            arguments: ["-f", expectURL.path],
            environment: environment
        )
    }

    @discardableResult
    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: String? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let environment {
            var merged = ProcessInfo.processInfo.environment
            merged.merge(environment) { _, new in new }
            process.environment = merged
        }

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()

        if let standardInput {
            let data = Data(standardInput.utf8)
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let status = process.terminationStatus
        guard status == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHCommandError.processFailed(message ?? "Command failed with status \(status)")
        }

        return status
    }

    static func sshpassPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/sshpass",
            "/usr/local/bin/sshpass",
            "/opt/local/bin/sshpass",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    enum SSHCommandError: LocalizedError {
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .processFailed(let message):
                return message
            }
        }
    }
}
