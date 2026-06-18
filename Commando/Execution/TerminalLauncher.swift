//
//  TerminalLauncher.swift
//  Commando
//

import AppKit
import Foundation

enum TerminalLauncher {

    enum LaunchError: LocalizedError {
        case appNotFound(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotFound(let path):
                return "Terminal app not found at \(path)."
            case .launchFailed(let message):
                return message
            }
        }
    }

    /// Stable, inspectable script path (reused each run).
    static var scriptURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Commando", isDirectory: true)
            .appendingPathComponent("run.command")
    }

    static func open(command: String, commandSetName: String, appPath: String) throws {
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw LaunchError.appNotFound(appPath)
        }

        let scriptURL = try writeCommandScript(command: command, commandSetName: commandSetName)
        let bundleId = Bundle(path: appPath)?.bundleIdentifier

        switch bundleId {
        case "com.apple.Terminal":
            try runInTerminal(scriptURL: scriptURL)
        case "com.googlecode.iterm2":
            try runInITerm(scriptURL: scriptURL)
        default:
            try openScript(inAppAt: appPath, scriptURL: scriptURL)
        }
    }

    static func wrappedCommand(_ command: String, commandSetName: String) -> String {
        let title = commandSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleBase64 = Data((title.isEmpty ? "Command Set" : title).utf8).base64EncodedString()

        return """
        user_shell="${SHELL:-/bin/zsh}"
        if [ ! -x "$user_shell" ]; then
            user_shell="/bin/zsh"
        fi
        shell_path="$("$user_shell" -lic 'printf "%s" "$PATH"' 2>/dev/null || true)"
        if [ -n "$shell_path" ]; then
            export PATH="$shell_path"
        fi

        command_set_name="$(printf '%s' '\(titleBase64)' | base64 -d)"
        printf '\\n==========Commando==========\\nRunning %s\\n============================\\n\\n' "$command_set_name"

        (
        set -e
        \(command)
        )
        status=$?
        if [ "$status" -ne 0 ]; then
            printf '\\nCommando command exited with status %s.\\n' "$status"
        fi
        exec "$user_shell" -l
        """
    }

    private static func writeCommandScript(command: String, commandSetName: String) throws -> URL {
        let url = scriptURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let scriptBody = "#!/bin/bash\n" + wrappedCommand(command, commandSetName: commandSetName) + "\n"
        try scriptBody.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static func runInTerminal(scriptURL: URL) throws {
        let path = appleScriptEscape(scriptURL.path)
        let source = """
        tell application "Terminal"
            activate
            do script "/bin/bash " & quoted form of "\(path)"
        end tell
        """
        try runAppleScript(source, failurePrefix: "Failed to open Terminal")
    }

    private static func runInITerm(scriptURL: URL) throws {
        let path = appleScriptEscape(scriptURL.path)
        let source = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile command "/bin/bash " & quoted form of "\(path)")
        end tell
        """
        try runAppleScript(source, failurePrefix: "Failed to open iTerm")
    }

    private static func openScript(inAppAt appPath: String, scriptURL: URL) throws {
        let appName = TerminalAppSettings.displayName(for: appPath)
        try runProcess(
            executable: "/usr/bin/open",
            arguments: ["-a", appPath, scriptURL.path],
            failurePrefix: "Failed to open \(appName)"
        )
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String, failurePrefix: String) throws {
        try runProcess(
            executable: "/usr/bin/osascript",
            arguments: ["-e", source],
            failurePrefix: failurePrefix
        )
    }

    private static func runProcess(executable: String, arguments: [String], failurePrefix: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.launchFailed("\(failurePrefix): \(message ?? "Unknown error")")
        }
    }
}
