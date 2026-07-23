//
//  TerminalLauncher.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import Darwin
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

    private enum TerminalKind {
        case terminal
        case iTerm
        case warp
        case ghostty
        case alacritty
        case wezTerm
        case generic
    }

    static func open(command: String, commandSetName: String, appPath: String) throws {
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw LaunchError.appNotFound(appPath)
        }

        let appAccess = TerminalAppSettings.securityScopedAccess(for: appPath)
        defer { appAccess.stopAccessingIfNeeded() }

        let appName = TerminalAppSettings.displayName(for: appPath)
        let terminal = terminalKind(for: appPath)
        let script = wrappedCommand(command, commandSetName: commandSetName)
        let home = realUserHomeDirectory()

        switch terminal {
            case .terminal:
                try runInTerminal(commandScript: script, appPath: appPath)
            case .iTerm:
                try runInITerm(commandScript: script, appPath: appPath)
            case .warp:
                try runInWarp(
                    commandScript: script,
                    commandSetName: commandSetName,
                    appPath: appPath,
                    workingDirectory: home
                )
            case .ghostty:
                try runInGhostty(
                    commandScript: script,
                    appPath: appPath,
                    workingDirectory: home
                )
            case .alacritty:
                try runInGenericTerminal(
                    commandScript: script,
                    appPath: appPath,
                    appName: appName,
                    launchArguments: { scriptURL in
                        ["-e", "/bin/bash", scriptURL.path]
                    }
                )
            case .wezTerm:
                try runInGenericTerminal(
                    commandScript: script,
                    appPath: appPath,
                    appName: appName,
                    launchArguments: { scriptURL in
                        ["start", "--", "/bin/bash", scriptURL.path]
                    }
                )
            case .generic:
                try runInGenericTerminal(
                    commandScript: script,
                    appPath: appPath,
                    appName: appName
                )
        }
    }

    static func wrappedCommand(_ command: String, commandSetName: String) -> String {
        let title = commandSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? "Command Set" : title
        let homeDirectory = realUserHomeDirectory()

        return """
        user_home=\(shellSingleQuoted(homeDirectory))
        if [ -d "$user_home" ]; then
            export HOME="$user_home"
            cd "$user_home"
        fi

        user_shell="${SHELL:-}"
        if [ -z "$user_shell" ] || [ ! -x "$user_shell" ]; then
            user_shell="$(/usr/bin/dscl . -read "/Users/$USER" UserShell 2>/dev/null | /usr/bin/awk '{print $2; exit}')"
        fi
        if [ -z "$user_shell" ] || [ ! -x "$user_shell" ]; then
            user_shell="/bin/zsh"
        fi

        shell_path="$($user_shell -lic 'printf "%s" "$PATH"' 2>/dev/null || true)"
        if [ -n "$shell_path" ]; then
            export PATH="$shell_path"
        fi

        /usr/bin/clear 2>/dev/null || printf '\033c'

        command_set_name=\(shellSingleQuoted(safeTitle))
        printf '\n========== Commando ==========\nRunning %s\n==============================\n\n' "$command_set_name"

        (
        set -e
        \(command)
        )
        status=$?

        if [ "$status" -ne 0 ]; then
            printf '\nCommando command exited with status %s.\n' "$status"
        fi

        exec "$user_shell" -l
        """
    }

    private static func terminalKind(for appPath: String) -> TerminalKind {
        let bundle = Bundle(path: appPath)
        let bundleId = bundle?.bundleIdentifier?.lowercased() ?? ""
        let displayName = TerminalAppSettings.displayName(for: appPath).lowercased()
        let executableName = bundle?.executableURL?.lastPathComponent.lowercased() ?? ""
        let pathName = (appPath as NSString).lastPathComponent.lowercased()
        let combined = [bundleId, displayName, executableName, pathName].joined(separator: " ")

        if bundleId == "com.apple.terminal" || displayName == "terminal" {
            return .terminal
        }

        if bundleId == "com.googlecode.iterm2" || combined.contains("iterm") {
            return .iTerm
        }

        if combined.contains("warp") {
            return .warp
        }

        if combined.contains("ghostty") {
            return .ghostty
        }

        if combined.contains("wezterm") || combined.contains("wez.wezterm") || combined.contains("wezfurlong") {
            return .wezTerm
        }

        if combined.contains("alacritty") {
            return .alacritty
        }

        return .generic
    }

    private struct SharedTerminalRun {
        let directoryURL: URL
        let scriptURL: URL
        let startedURL: URL
    }

    private static var sharedTerminalRunRootURL: URL {
        AppStoragePaths.terminalRunsDirectory
    }

    private static func cleanupOldSharedTerminalRuns(in root: URL) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let cutoff = Date().addingTimeInterval(-60 * 60 * 24)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func writeSharedTerminalRun(
        commandScript: String,
        rootURL: URL = sharedTerminalRunRootURL
    ) throws -> SharedTerminalRun {
        cleanupOldSharedTerminalRuns(in: rootURL)

        let directoryURL = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scriptURL = directoryURL.appendingPathComponent("run.sh")
        let startedURL = directoryURL.appendingPathComponent("started")

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )

            let script = "#!/bin/bash\n/usr/bin/touch " + shellSingleQuoted(startedURL.path) + " 2>/dev/null || true\n" + commandScript + "\n"
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            return SharedTerminalRun(directoryURL: directoryURL, scriptURL: scriptURL, startedURL: startedURL)

        } catch {
            throw LaunchError.launchFailed(
                "Commando could not prepare the command for this terminal. Underlying error: \(error.localizedDescription)"
            )
        }
    }

    private static func scriptFileLauncherCommand(_ scriptPath: String) -> String {
        "/usr/bin/clear; /bin/bash " + shellSingleQuoted(scriptPath)
    }

    private static func scriptFileLauncherBashCommand(_ scriptPath: String) -> String {
        "/bin/bash -lc " + shellSingleQuoted(scriptFileLauncherCommand(scriptPath))
    }

    private static func inlineLauncherBashCommand(_ commandScript: String) -> String {
        let encodedScript = Data(commandScript.utf8).base64EncodedString()
        let pipeline = "/usr/bin/printf '%s' "
            + shellSingleQuoted(encodedScript)
            + " | /usr/bin/base64 -d | /bin/bash"

        return "/bin/bash -lc " + shellSingleQuoted(pipeline)
    }

    private static func runInTerminal(commandScript: String, appPath: String) throws {
        try ensureApplicationIsRunning(bundleIdentifier: "com.apple.Terminal", appPath: appPath)

        let run = try writeSharedTerminalRun(commandScript: commandScript)
        let command = appleScriptStringLiteral(scriptFileLauncherCommand(run.scriptURL.path))
        let source = """
        tell application id "com.apple.Terminal"
            activate
            do script \(command)
        end tell
        """

        try runAppleScript(source, failurePrefix: "Failed to open Terminal")
    }

    private static func runInITerm(commandScript: String, appPath: String) throws {
        try ensureApplicationIsRunning(bundleIdentifier: "com.googlecode.iterm2", appPath: appPath)

        let run = try writeSharedTerminalRun(commandScript: commandScript)
        let command = appleScriptStringLiteral(scriptFileLauncherBashCommand(run.scriptURL.path))
        let source = """
        tell application id "com.googlecode.iterm2"
            activate
            create window with default profile command \(command)
        end tell
        """


        try runAppleScript(source, failurePrefix: "Failed to open iTerm")

    }

    private static func runInGhostty(commandScript: String, appPath: String, workingDirectory: String) throws {
        let bundleId = Bundle(path: appPath)?.bundleIdentifier ?? "com.mitchellh.ghostty"
        let wasRunning = isApplicationRunning(appPath: appPath)

        try ensureApplicationIsRunning(bundleIdentifier: bundleId, appPath: appPath)

        let applicationId = appleScriptStringLiteral(bundleId)
        let cwd = appleScriptStringLiteral(workingDirectory)
        // Ghostty is sandboxed. Pointing it at a file inside Commando's app
        // container causes macOS to ask for cross-app data access on every run.
        // Pass the script inline instead, encoded so arbitrary shell content is
        // preserved without exposing a container path.
        let command = appleScriptStringLiteral(inlineLauncherBashCommand(commandScript))

        let source: String
        if wasRunning {
            source = """
            tell application id \(applicationId)
                activate
                set cfg to new surface configuration
                set initial working directory of cfg to \(cwd)
                set command of cfg to \(command)
                set wait after command of cfg to true
                set win to new window with configuration cfg
            end tell
            """
        } else {
            source = """
            tell application id \(applicationId)
                set cfg to new surface configuration
                set initial working directory of cfg to \(cwd)
                set command of cfg to \(command)
                set wait after command of cfg to true
                set win to new window with configuration cfg
                activate
            end tell
            """
        }

        try runAppleScript(source, failurePrefix: "Failed to open Ghostty")
    }

    private static func runInWarp(
        commandScript: String,
        commandSetName: String,
        appPath: String,
        workingDirectory: String
    ) throws {
        let title = commandSetName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Commando"
        let wasRunning = isApplicationRunning(appPath: appPath)
        let tabConfigName = "commando"

        var warpAccess = WarpConfigAccess.securityScopedAccess(for: appPath)
        if warpAccess.url == nil {
            guard WarpConfigAccess.promptForAccess(for: appPath) else {
                throw LaunchError.launchFailed(
                    "Commando needs access to your Warp configuration folder to open command sets in Warp. You can grant access when prompted, or choose another terminal app in Settings."
                )
            }
            warpAccess = WarpConfigAccess.securityScopedAccess(for: appPath)
        }

        guard let warpRoot = warpAccess.url else {
            throw LaunchError.launchFailed(
                "Commando could not access your Warp configuration folder. Try choosing Warp again in Settings."
            )
        }

        defer { warpAccess.stopAccessingIfNeeded() }

        // Warp is sandboxed. If its command points into Commando's container,
        // macOS asks the user for cross-app data access on every run. Keep
        // Warp-specific runner scripts in the already-authorized Warp config
        // directory instead.
        let runRootURL = warpRoot.appendingPathComponent("commando-runs", isDirectory: true)
        let run = try writeSharedTerminalRun(commandScript: commandScript, rootURL: runRootURL)
        let command = scriptFileLauncherCommand(run.scriptURL.path)
        let tabDirectoryURL = warpRoot.appendingPathComponent("tab_configs", isDirectory: true)
        let tabConfigURL = tabDirectoryURL.appendingPathComponent("\(tabConfigName).toml")

        let toml = """
        name = "Commando"
        title = \(tomlDoubleQuoted(title))
        color = "blue"

        [[panes]]
        id = "main"
        type = "terminal"
        directory = \(tomlDoubleQuoted(workingDirectory))
        commands = [\(tomlDoubleQuoted(command))]
        is_focused = true
        """

        do {
            try FileManager.default.createDirectory(
                at: tabDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )

            try toml.write(to: tabConfigURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tabConfigURL.path)
        } catch {
            throw LaunchError.launchFailed(
                "Failed to write Warp tab config at \(tabConfigURL.path): \(error.localizedDescription)"
            )
        }

        let scheme = warpURLScheme(for: appPath)
        let newWindowValue = wasRunning ? "true" : "false"

        guard let url = URL(string: "\(scheme)://tab_config/\(tabConfigName)?new_window=\(newWindowValue)") else {
            throw LaunchError.launchFailed("Failed to open Warp: could not build Warp tab config URL.")
        }

        guard NSWorkspace.shared.open(url) else {
            throw LaunchError.launchFailed("Failed to open Warp: Warp rejected the tab config URL.")
        }
    }

    private static func runInGenericTerminal(
        commandScript: String,
        appPath: String,
        appName: String,
        launchArguments: ((URL) -> [String])? = nil
    ) throws {
        let run = try writeSharedTerminalRun(commandScript: commandScript)
        let arguments = launchArguments?(run.scriptURL) ?? ["-e", "/bin/bash", run.scriptURL.path]

        do {
            try launchSelectedTerminalAppWithArguments(
                appPath: appPath,
                appName: appName,
                arguments: arguments,
                run: run
            )
        } catch {
            throw LaunchError.launchFailed(
                "Commando tried to run this command in \(appName) which didn't work. Commando officially supports \(TerminalAppSettings.supportedTerminalNames.joined(separator: ", ")). \n\nUnderlying error: \(error.localizedDescription)"
            )
        }
    }

    private static func launchSelectedTerminalAppWithArguments(
        appPath: String,
        appName: String,
        arguments: [String],
        run: SharedTerminalRun
    ) throws {
        let appURL = URL(fileURLWithPath: appPath, isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()


        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        configuration.environment = userTerminalControlEnvironment()

        var didFinish = false
        var launchedApp: NSRunningApplication?
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            launchedApp = app
            launchError = error
            didFinish = true
        }

        try waitForAsyncWorkspaceResult(
            didFinish: { didFinish },
            timeoutMessage: "Failed to open \(appName): timed out while launching the app."
        )

        if let launchError = launchError {
            throw LaunchError.launchFailed("Failed to open \(appName): \(launchError.localizedDescription)")
        }

        if let launchedApp = launchedApp {
            try waitForApplicationToFinishLaunching(launchedApp, appName: appName)
        }

        activateApplication(appPath: appPath)

        guard waitForSharedTerminalRunToStart(run) else {
            throw LaunchError.launchFailed(
                "\(appName) opened, but macOS did not pass Commando's command arguments to it."
            )
        }
    }

    private static func waitForSharedTerminalRunToStart(_ run: SharedTerminalRun) -> Bool {
        let deadline = Date().addingTimeInterval(15.0)

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: run.startedURL.path) {
                return true
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return FileManager.default.fileExists(atPath: run.startedURL.path)
    }

    private static func isApplicationRunning(appPath: String) -> Bool {
        if let bundleId = Bundle(path: appPath)?.bundleIdentifier {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
        }

        let resolvedPath = URL(fileURLWithPath: appPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .path

        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleURL?.resolvingSymlinksInPath().path == resolvedPath
        }
    }

    private static func activateApplication(appPath: String) {
        if let bundleId = Bundle(path: appPath)?.bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateIgnoringOtherApps])

            return
        }

        let resolvedPath = URL(fileURLWithPath: appPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .path

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.resolvingSymlinksInPath().path == resolvedPath
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func ensureApplicationIsRunning(bundleIdentifier: String, appPath: String) throws {
        let appName = TerminalAppSettings.displayName(for: appPath)

        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            try waitForApplicationToFinishLaunching(runningApp, appName: appName)

            return
        }

        let appURL = URL(fileURLWithPath: appPath, isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()

        configuration.activates = false

        var didFinish = false
        var launchedApp: NSRunningApplication?
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            launchedApp = app
            launchError = error
            didFinish = true
        }

        try waitForAsyncWorkspaceResult(
            didFinish: { didFinish },
            timeoutMessage: "Failed to open \(appName): timed out while launching the app."
        )

        if let launchError = launchError {
            throw LaunchError.launchFailed("Failed to open \(appName): \(launchError.localizedDescription)")
        }

        guard let launchedApp = launchedApp else {
            throw LaunchError.launchFailed("Failed to open \(appName): the app did not launch.")
        }

        try waitForApplicationToFinishLaunching(launchedApp, appName: appName)
    }

    private static func waitForApplicationToFinishLaunching(_ app: NSRunningApplication, appName: String) throws {
        let deadline = Date().addingTimeInterval(10)

        while !app.isFinishedLaunching && !app.isTerminated && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if app.isTerminated {
            throw LaunchError.launchFailed("Failed to open \(appName): the app quit before it finished launching.")
        }

        guard app.isFinishedLaunching else {
            throw LaunchError.launchFailed("Failed to open \(appName): timed out while waiting for the app to finish launching.")
        }
    }

    private static func waitForAsyncWorkspaceResult(
        didFinish: () -> Bool,
        timeoutMessage: String
    ) throws {
        let deadline = Date().addingTimeInterval(10)

        while !didFinish() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard didFinish() else {
            throw LaunchError.launchFailed(timeoutMessage)
        }
    }

    private static func runAppleScript(_ source: String, failurePrefix: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw LaunchError.launchFailed("\(failurePrefix): failed to compile script.")
        }

        // Launch Services can report an application as ready a moment before its
        // Apple Events endpoint is registered. Retry only the transient -600
        // ("Application isn't running") response; all other failures surface
        // immediately, including Automation permission denials.
        let deadline = Date().addingTimeInterval(5)
        var errorInfo: NSDictionary?

        repeat {
            errorInfo = nil
            script.executeAndReturnError(&errorInfo)

            guard let errorInfo,
                  (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -600,
                  Date() < deadline else {
                break
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.15))
        } while true

        if let errorInfo = errorInfo {
            throw LaunchError.launchFailed("\(failurePrefix): \(appleScriptErrorMessage(from: errorInfo))")
        }
    }

    private static func appleScriptErrorMessage(from errorInfo: NSDictionary) -> String {
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        let number = errorInfo[NSAppleScript.errorNumber] as? NSNumber

        switch (message, number) {
            case let (message?, number?):
                return "\(message) (\(number))"
            case let (message?, nil):
                return message
            case let (nil, number?):
                return "AppleScript error \(number)"
            default:
                return "Unknown AppleScript error"
        }
    }

    private static func userTerminalControlEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = realUserHomeDirectory()
        let user = realUserName()
        let shell = realUserShell()

        environment["HOME"] = home
        environment["USER"] = user
        environment["LOGNAME"] = user
        environment["SHELL"] = shell
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["XDG_DATA_HOME"] = home + "/.local/share"
        environment["XDG_CONFIG_HOME"] = home + "/.config"

        environment.removeValue(forKey: "WEZTERM_UNIX_SOCKET")
        environment.removeValue(forKey: "WEZTERM_PANE")
        environment.removeValue(forKey: "ALACRITTY_SOCKET")

        return environment
    }

    private static func realUserHomeDirectory() -> String {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return String(cString: home)
        }

        return NSHomeDirectory()
    }

    private static func realUserName() -> String {
        if let passwd = getpwuid(getuid()), let name = passwd.pointee.pw_name {
            return String(cString: name)
        }

        return NSUserName()
    }

    private static func realUserShell() -> String {
        if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
            let value = String(cString: shell)
            if !value.isEmpty { return value }
        }
        
        return "/bin/zsh"
    }

    private static func warpURLScheme(for appPath: String) -> String {
        let bundleId = Bundle(path: appPath)?.bundleIdentifier?.lowercased() ?? ""
        let displayName = TerminalAppSettings.displayName(for: appPath).lowercased()
        let pathName = (appPath as NSString).lastPathComponent.lowercased()

        if bundleId.contains("preview") || displayName.contains("preview") || pathName.contains("preview") {
            return "warppreview"
        }

        return "warp"
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func tomlDoubleQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
