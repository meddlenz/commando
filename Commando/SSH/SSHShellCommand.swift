//
//  SSHShellCommand.swift
//  Commando
//  Jordan Trbuhovic 2026
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

        // Run from a temp script file so `ssh -t` keeps a PTY and `exec bash -i` works.
        let encoded = Data(remoteScript.utf8).base64EncodedString()
        let remoteCommand = "f=$(mktemp /tmp/commandrunner.XXXXXX.sh) && echo \(encoded) | base64 -d > \"$f\" && bash \"$f\"; e=$?; rm -f \"$f\"; exit $e"
        
        return "\(sshLine) \(shellQuote(remoteCommand))"
    }

    static func wrapForTerminal(_ command: String, password: String) -> String {
        let passwordBase64 = Data(password.utf8).base64EncodedString()
        let commandBase64 = Data(command.utf8).base64EncodedString()
        let expectWrapper = wrapWithExpectForTerminal(
            command: command,
            password: password,
            interactive: command.contains(" -t ")
        )

        return """
        SSHPASS_BIN=""
        for candidate in /opt/homebrew/bin/sshpass /usr/local/bin/sshpass /opt/local/bin/sshpass; do
          if [ -x "$candidate" ]; then SSHPASS_BIN="$candidate"; break; fi
        done
        if [ -n "$SSHPASS_BIN" ]; then
          export SSHPASS=$(echo '\(passwordBase64)' | base64 -d)
          echo '\(commandBase64)' | base64 -d | "$SSHPASS_BIN" -e /bin/bash -s
          STATUS=$?
          unset SSHPASS
          exit $STATUS
        fi
        \(expectWrapper)
        """
    }

    private static func wrapWithExpectForTerminal(command: String, password: String, interactive: Bool) -> String {
        let commandBase64 = Data(command.utf8).base64EncodedString()
        let expectBody = expectScriptBody(interactive: interactive)

        return """
        export CR_PASSWORD=\(shellQuote(password)); \
        SCRIPT_FILE=$(mktemp -t commandrunner.XXXXXX.sh); \
        echo '\(commandBase64)' | base64 -d > "$SCRIPT_FILE"; chmod 700 "$SCRIPT_FILE"; \
        export SCRIPT_FILE; \
        EXPECT_FILE=$(mktemp -t commandrunner.XXXXXX.exp); \
        cat > "$EXPECT_FILE" << 'EXPECTEOF'
        \(expectBody)
        EXPECTEOF
        chmod 700 "$EXPECT_FILE"; \
        /usr/bin/expect -f "$EXPECT_FILE"; \
        STATUS=$?; rm -f "$EXPECT_FILE" "$SCRIPT_FILE"; unset CR_PASSWORD; exit $STATUS
        """

    }

    private static func expectScriptBody(interactive: Bool) -> String {
        let passwordContinuation = interactive ? "        interact" : "        exp_continue"
        var lines = [
            "#!/usr/bin/expect -f",
            "set timeout 120",
            "set password $env(CR_PASSWORD)",
            "set scriptFile $env(SCRIPT_FILE)",
            "spawn /bin/bash $scriptFile",
            "expect {",
            "    -re {(?i)(yes/no|continue connecting|fingerprint)} {",
            "        send \"yes\\r\"",
            "        exp_continue",
            "    }",
            "    -re {(?i)password:} {",
            "        send \"$password\\r\"",
            passwordContinuation,
            "    }",
            "    timeout {",
            "        send_error \"Timed out waiting for the SSH server.\\n\"",
            "        catch close",
            "        catch wait",
            "        exit 124",
            "    }",
            "    eof {}",
            "}",
        ]

        if interactive {
            lines += [
                "catch wait result",
                "exit [lindex $result 3]",
            ]
        } else {
            lines += [
                "catch wait result",
                "exit [lindex $result 3]",
            ]
        }

        return lines.joined(separator: "\n")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
