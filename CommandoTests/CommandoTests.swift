//
//  CommandoTests.swift
//  CommandoTests
//

import XCTest
@testable import Commando

class CommandoTests: XCTestCase {

    func testSSHConnectionParsesHostWithoutPort() {
        let connection = SSHConnection.parse(from: "deploy@example.com")
        XCTAssertEqual(connection?.username, "deploy")
        XCTAssertEqual(connection?.host, "example.com")
        XCTAssertNil(connection?.port)
    }

    func testSSHConnectionParsesHostWithPort() {
        let connection = SSHConnection.parse(from: "deploy@example.com:2222")
        XCTAssertEqual(connection?.username, "deploy")
        XCTAssertEqual(connection?.host, "example.com")
        XCTAssertEqual(connection?.port, 2222)
    }

    func testSSHConnectionRejectsInvalidInput() {
        XCTAssertNil(SSHConnection.parse(from: ""))
        XCTAssertNil(SSHConnection.parse(from: "not-valid"))
        XCTAssertNil(SSHConnection.parse(from: "@host"))
    }

    func testCommandSetDecodesParallelSessions() throws {
        let json = """
        {"name":"Stack","sessions":[["cd frontend","npm run dev"],["cd backend","npm start"]]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)

        XCTAssertEqual(commandSet.sessions.map(\.steps), [["cd frontend", "npm run dev"], ["cd backend", "npm start"]])
        XCTAssertEqual(commandSet.nonEmptySessions.count, 2)
        XCTAssertEqual(commandSet.stepsSummary, "2 sessions")
    }

    func testCommandSetDecodesNamedSessions() throws {
        let json = """
        
        {"name":"Stack","sessions":[{"name":"Frontend","steps":["npm run dev"]},{"name":"Backend","steps":["npm start"]}]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)
        XCTAssertEqual(commandSet.sessions.map(\.name), ["Frontend", "Backend"])
        XCTAssertEqual(commandSet.sessions.map(\.steps), [["npm run dev"], ["npm start"]])
    }

    func testCommandSetLegacyStepsBecomeOneSession() throws {
        let json = """
        {"name":"Legacy","commands":["echo hello","echo world"]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)
        XCTAssertEqual(commandSet.name, "Legacy")
        XCTAssertEqual(commandSet.sessions.map(\.steps), [["echo hello", "echo world"]])
        XCTAssertEqual(commandSet.nonEmptySteps, ["echo hello", "echo world"])
        XCTAssertTrue(commandSet.serverDetails.isEmpty)
    }

    func testTerminalCommandsReturnsOneCommandPerSession() throws {
        let commandSet = CommandSet(
            name: "Dev",
            sessions: [
                CommandSession(steps: ["cd frontend", "npm run dev"]),
                CommandSession(steps: ["cd backend", "npm start"])
            ]
        )

        let commands = try CommandExecutor.terminalCommands(for: commandSet)
        XCTAssertEqual(commands, ["cd frontend\nnpm run dev", "cd backend\nnpm start"])
    }

    func testTerminalCommandsSSHWrapsEachSession() throws {
        let commandSet = CommandSet(
            name: "Remote",
            serverDetails: "root@vultr",
            sessions: [CommandSession(steps: ["uptime"]), CommandSession(steps: ["df -h"])]
        )

        let commands = try CommandExecutor.terminalCommands(for: commandSet)
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands[0].contains("root@vultr"))
        XCTAssertTrue(commands[1].contains("root@vultr"))
        XCTAssertNotEqual(commands[0], commands[1])
    }

    func testITermScriptSplitsInsteadOfOpeningWindows() {
        let split = TerminalLauncher.iTermScript(commands: ["'one'", "'two'", "'three'"], split: true)
        XCTAssertTrue(split.contains("create window with default profile command 'one'"))
        XCTAssertTrue(split.contains("split vertically with default profile command 'two'"))
        XCTAssertTrue(split.contains("split vertically with default profile command 'three'"))
        XCTAssertEqual(split.components(separatedBy: "create window").count - 1, 1)

        let windows = TerminalLauncher.iTermScript(commands: ["'one'", "'two'"], split: false)
        XCTAssertEqual(windows.components(separatedBy: "create window").count - 1, 2)
        XCTAssertFalse(windows.contains("split vertically"))
    }

    func testGhosttyScriptSplitsInsteadOfOpeningWindows() {
        let split = TerminalLauncher.ghosttyScript(
            bundleId: "com.mitchellh.ghostty",
            cwd: "\"/Users/test\"",
            commands: ["\"one\"", "\"two\""],
            split: true,
            activateFirst: true
        )
        XCTAssertTrue(split.contains("new window with configuration cfg0"))
        XCTAssertTrue(split.contains("split pane0 direction right with configuration cfg1"))
        XCTAssertFalse(split.contains("new window with configuration cfg1"))

        let windows = TerminalLauncher.ghosttyScript(
            bundleId: "com.mitchellh.ghostty",
            cwd: "\"/Users/test\"",
            commands: ["\"one\"", "\"two\""],
            split: false,
            activateFirst: true
        )
        XCTAssertTrue(windows.contains("new window with configuration cfg0"))
        XCTAssertTrue(windows.contains("new window with configuration cfg1"))
        XCTAssertFalse(windows.contains("split pane"))
    }

    func testWarpTabConfigSplitsParallelSessions() {
        let single = TerminalLauncher.warpTabConfigTOML(
            title: "Solo",
            workingDirectory: "/Users/test",
            paneCommands: ["/bin/bash run.sh"]
        )
        XCTAssertTrue(single.contains("id = \"main\""))
        XCTAssertFalse(single.contains("split = \"horizontal\""))

        let parallel = TerminalLauncher.warpTabConfigTOML(
            title: "Stack",
            workingDirectory: "/Users/test",
            paneCommands: ["cmd1", "cmd2"]
        )
        XCTAssertTrue(parallel.contains("split = \"horizontal\""))
        XCTAssertTrue(parallel.contains("children = [\"p0\", \"p1\"]"))
        XCTAssertTrue(parallel.contains("id = \"p0\""))
        XCTAssertTrue(parallel.contains("id = \"p1\""))
    }

    func testCommandSetNonEmptyStepsIgnoresBlankLines() {
        let commandSet = CommandSet(
            name: "Test",
            steps: ["  echo one  ", "", "echo two"]
        )
        XCTAssertEqual(commandSet.nonEmptySteps, ["echo one", "echo two"])
    }

    func testCommandSetDecodesStructuredStepsWithoutDelayKind() throws {
        let json = """
        {"name":"Structured","steps":[{"kind":"command","text":"cd leg/"},{"kind":"command","text":"ls"}]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)
        XCTAssertEqual(commandSet.nonEmptySteps, ["cd leg/", "ls"])
    }

    func testCommandSetMigratesDelayStepsToSleepCommands() throws {
        let json = """
        {"name":"Delay","steps":[{"kind":"delay","text":"5"},{"kind":"command","text":"ls"}]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)
        XCTAssertEqual(commandSet.nonEmptySteps, ["sleep 5", "ls"])
    }

    func testTerminalAppSettingsDefaultPathExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: TerminalAppSettings.defaultPath))
    }

    func testTerminalAppSettingsDisplayName() {
        let name = TerminalAppSettings.displayName(for: TerminalAppSettings.defaultPath)
        XCTAssertFalse(name.isEmpty)
    }

    func testWarpConfigAccessRequiresExactHiddenDirectory() {
        let warpPath = "/Applications/Warp.app"
        let expected = WarpConfigAccess.defaultConfigDirectoryURL(for: warpPath)

        XCTAssertTrue(WarpConfigAccess.isExpectedConfigDirectory(expected, for: warpPath))
        XCTAssertFalse(
            WarpConfigAccess.isExpectedConfigDirectory(
                expected.deletingLastPathComponent(),
                for: warpPath
            )
        )
    }

    func testWarpPreviewUsesPreviewConfigDirectory() {
        XCTAssertEqual(
            WarpConfigAccess.configDirectoryName(for: "/Applications/WarpPreview.app"),
            ".warp-preview"
        )
    }

    func testSSHStepParserParsesBareSSHCommand() {
        let connection = SSHStepParser.parseBareSSHCommand("ssh admin@256.256.256.256")
        XCTAssertEqual(connection?.username, "admin")
        XCTAssertEqual(connection?.host, "256.256.256.256")
        XCTAssertNil(SSHStepParser.remoteCommand(from: "ssh admin@256.256.256.256"))
    }

    func testSSHStepParserParsesSSHWithPortAndRemoteCommand() {
        let connection = SSHStepParser.parseBareSSHCommand("ssh -p 2222 deploy@example.com uptime")
        XCTAssertEqual(connection?.port, 2222)
        XCTAssertEqual(SSHStepParser.remoteCommand(from: "ssh -p 2222 deploy@example.com uptime"), "uptime")
    }

    func testSSHConnectionStripsSSHPrefixFromServerField() {
        let connection = SSHConnection.parse(from: "ssh admin@256.256.256.256")
        XCTAssertEqual(connection?.username, "admin")
        XCTAssertEqual(connection?.host, "256.256.256.256")
    }

    func testRemoteScriptKeepsSessionOpen() {
        let script = SSHShellCommand.remoteScript(from: ["cd leg/"], keepSessionOpen: true)
        XCTAssertEqual(script, "set -e\ncd leg/\nexec bash -i </dev/tty")
    }

    func testRemoteScriptUsesOneLinePerStep() {
        let script = SSHShellCommand.remoteScript(from: ["cd leg/", "npm install"], keepSessionOpen: true)
        XCTAssertEqual(script, "set -e\ncd leg/\nnpm install\nexec bash -i </dev/tty")
    }

    func testSSHShellCommandBuildsSingleShellCommand() {
        let connection = SSHConnection(username: "root", host: "108.61.150.182", port: nil)
        let command = SSHShellCommand.build(
            connection: connection,
            remoteScript: "cd legacyai",
            interactive: false
        )
        XCTAssertTrue(command.contains("root@108.61.150.182"))
        XCTAssertTrue(command.contains("mktemp /tmp/commandrunner"))
        XCTAssertTrue(command.contains("base64 -d"))
    }

    func testSSHBuildUsesTempScriptFile() {
        let connection = SSHConnection(username: "root", host: "example.com", port: nil)
        let command = SSHShellCommand.build(
            connection: connection,
            remoteScript: "cd leg/\nexec bash -i </dev/tty",
            interactive: true
        )
        XCTAssertTrue(command.contains(" -t "))
        XCTAssertTrue(command.contains("mktemp /tmp/commandrunner"))
        XCTAssertFalse(command.contains("bash -s"))
        XCTAssertFalse(command.contains("<<"))
    }

    func testSSHRemoteScriptChainsCommands() throws {
        let commandSet = CommandSet(
            name: "List files",
            serverDetails: "root@vultr",
            steps: ["ls"]
        )

        let command = try CommandExecutor.terminalCommand(for: commandSet)
        XCTAssertTrue(command.contains("ssh "))
        XCTAssertTrue(command.contains("root@vultr"))
        XCTAssertTrue(command.contains("mktemp /tmp/commandrunner"))

        let remoteScript = SSHShellCommand.remoteScript(from: commandSet.nonEmptySteps, keepSessionOpen: true)
        XCTAssertEqual(remoteScript, "set -e\nls\nexec bash -i </dev/tty")
    }

    func testSSHRemoteCommandCanOpenSessionWithoutSteps() throws {
        let commandSet = CommandSet(
            name: "Server shell",
            serverDetails: "root@vultr",
            steps: [""]
        )

        let command = try CommandExecutor.terminalCommand(for: commandSet)
        XCTAssertTrue(command.contains("ssh "))
        XCTAssertTrue(command.contains("root@vultr"))
        XCTAssertTrue(command.contains("mktemp /tmp/commandrunner"))

        let remoteScript = SSHShellCommand.remoteScript(from: commandSet.nonEmptySteps, keepSessionOpen: true)
        XCTAssertEqual(remoteScript, "exec bash -i </dev/tty")
    }

    func testRemoteScriptPreservesCdForNextStep() {
        let script = SSHShellCommand.remoteScript(from: ["cd leg/", "npm install"], keepSessionOpen: false)
        XCTAssertEqual(script, "set -e\ncd leg/\nnpm install")
    }

    func testTerminalLauncherWrapsCommandWithLoginShell() {
        let wrapped = TerminalLauncher.wrappedCommand("cd leg/\nls", commandSetName: "Test Set")
        XCTAssertTrue(wrapped.contains("user_shell=\"${SHELL:-}\""))
        XCTAssertTrue(wrapped.contains("Running %s"))
        XCTAssertTrue(wrapped.contains("cd leg/"))
        XCTAssertTrue(wrapped.contains("ls"))
        XCTAssertTrue(wrapped.contains("exec \"$user_shell\" -l"))
        XCTAssertTrue(wrapped.contains("{\nset -e\ncd leg/\nls\n}"))
        XCTAssertTrue(wrapped.contains("set +e"))
        XCTAssertFalse(wrapped.contains("(\nset -e"))
    }

    func testPaneTitleUsesSessionNameInsteadOfNumber() {
        XCTAssertEqual(
            TerminalLauncher.paneTitle(commandSetName: "Parallel test", sessionName: "", index: 1, count: 2),
            "Parallel test (2)"
        )
        XCTAssertEqual(
            TerminalLauncher.paneTitle(commandSetName: "Parallel test", sessionName: "Frontend", index: 1, count: 2),
            "Parallel test (Frontend)"
        )
        XCTAssertEqual(
            TerminalLauncher.paneTitle(commandSetName: "Parallel test", sessionName: "", index: 0, count: 1),
            "Parallel test"
        )
    }

    func testInlineTerminalLauncherPreservesTerminalInput() {
        let launcher = TerminalLauncher.inlineLauncherBashCommand("ssh -t user@example.com")
        XCTAssertTrue(launcher.contains("> \"$script_file\""))
        XCTAssertTrue(launcher.contains("/bin/bash \"$script_file\""))
        XCTAssertFalse(launcher.contains("| /bin/bash"))
    }

    func testUpdateCheckerComparesSemanticVersions() {
        XCTAssertTrue(UpdateChecker.isVersion("2.1", greaterThan: "1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", greaterThan: "2.1"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", greaterThan: "1.0"))
    }

    func testUpdateCheckerSelectsDownloadURLByDistributionChannel() {
        let directURL = URL(string: "https://files.mac-attic.com/commando.dmg")!
        let appStoreURL = URL(string: "https://apps.apple.com/app/id123")!
        let blockedURL = URL(string: "https://evil.example/phish")!

        XCTAssertEqual(
            UpdateChecker.updateURL(macOSUrl: directURL, macAppStoreUrl: appStoreURL, isMacAppStore: false),
            directURL
        )
        XCTAssertEqual(
            UpdateChecker.updateURL(macOSUrl: directURL, macAppStoreUrl: appStoreURL, isMacAppStore: true),
            appStoreURL
        )
        XCTAssertNil(UpdateChecker.updateURL(macOSUrl: blockedURL, macAppStoreUrl: appStoreURL, isMacAppStore: false))
        XCTAssertFalse(UpdateChecker.isAllowedUpdateURL(URL(string: "file:///tmp/evil")!))
        XCTAssertEqual(UpdateChecker.updateActionTitle(isMacAppStore: false), "Download")
        XCTAssertEqual(UpdateChecker.updateActionTitle(isMacAppStore: true), "View in App Store")
    }

    func testCommandSetDocumentEncodesVersion() throws {
        let commandSet = CommandSet(name: "Dev", steps: ["echo hi"])
         let data = try CommandSetDocument.encode([commandSet])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"version\""))
        XCTAssertTrue(json.contains("1"))

        let payload = try CommandSetDocument.decodePayload(data)

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.commandSets.count, 1)
        XCTAssertEqual(payload.commandSets[0].name, "Dev")
        XCTAssertEqual(payload.commandSets[0].nonEmptySteps, ["echo hi"])
    }

    func testCommandSetDocumentRejectsNewerVersion() {
        let json = """
        {"version":99,"commandSets":[]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try CommandSetDocument.decode(json)) { error in
            guard case CommandSetDocument.DocumentError.unsupportedVersion(99) = error else {
                XCTFail("Expected unsupportedVersion, got \(error)")

                return
            }
        }
    }

    func testCommandSetDocumentDecodesUnversionedArray() throws {
        let json = """
        [{"name":"Legacy","steps":["echo hello"]}]
        """.data(using: .utf8)!

        let commandSets = try CommandSetDocument.decode(json)

        XCTAssertEqual(commandSets.count, 1)
        XCTAssertEqual(commandSets[0].name, "Legacy")
        XCTAssertEqual(commandSets[0].nonEmptySteps, ["echo hello"])
    }

    func testCommandSetDocumentMergesByID() {
        let sharedID = UUID()
        let local = [
            CommandSet(id: sharedID, name: "Local", steps: ["echo local"]),
            CommandSet(name: "Only Local", steps: ["echo a"]),
        ]

        let imported = [
            CommandSet(id: sharedID, name: "Imported", steps: ["echo imported"]),
            CommandSet(name: "Only Imported", steps: ["echo b"]),
        ]

        let merged = CommandSetDocument.merge(local, with: imported)

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].id, sharedID)
        XCTAssertEqual(merged[0].name, "Imported")
        XCTAssertEqual(merged[1].name, "Only Local")
        XCTAssertEqual(merged[2].name, "Only Imported")
    }

    func testCommandSetDocumentDecodesEncryptedUserDefaultsBlob() throws {
        let sample = [CommandSet(name: "Secure", serverDetails: "user@example.com", steps: ["echo hi"])]
        let json = try JSONEncoder().encode(sample)

        let encrypted = try SecureDataStore.encrypt(json)
        let loaded = try CommandSetDocument.decodeStoredData(encrypted)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Secure")
        XCTAssertEqual(loaded[0].serverDetails, "user@example.com")
        XCTAssertEqual(loaded[0].nonEmptySteps, ["echo hi"])
    }

    func testCommandSetsRoundTripThroughJSONFile() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let originalOverride = CommandStore.storageDirectoryOverride

        CommandStore.storageDirectoryOverride = directory
        CommandStore.resetCache()

        defer {
            CommandStore.storageDirectoryOverride = originalOverride
            CommandStore.resetCache()

            try? FileManager.default.removeItem(at: directory)
        }

        let sample = [
            CommandSet(name: "Secure", serverDetails: "user@example.com", steps: ["echo hi"]),
        ]

        CommandStore.commandSets = sample
        CommandStore.resetCache()

        let loaded = CommandStore.commandSets

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Secure")
        XCTAssertEqual(loaded[0].serverDetails, "user@example.com")
        XCTAssertEqual(loaded[0].nonEmptySteps, ["echo hi"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("command-sets.json").path))
    }

    func testCommandStoreImportMergeAndReplace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let originalOverride = CommandStore.storageDirectoryOverride

        CommandStore.storageDirectoryOverride = directory
        CommandStore.resetCache()

        defer {
            CommandStore.storageDirectoryOverride = originalOverride
            CommandStore.resetCache()

            try? FileManager.default.removeItem(at: directory)
        }

        let sharedID = UUID()

        CommandStore.commandSets = [
            CommandSet(id: sharedID, name: "Local", steps: ["echo local"]),
            CommandSet(name: "Keep", steps: ["echo keep"]),
        ]

        let importURL = directory.appendingPathComponent("import.json")
        let imported = [
            CommandSet(id: sharedID, name: "Imported", steps: ["echo imported"]),
            CommandSet(name: "New", steps: ["echo new"]),
        ]
        try CommandSetDocument.encode(imported).write(to: importURL)

        try CommandStore.importDocument(from: importURL, mode: .merge)
        XCTAssertEqual(CommandStore.commandSets.count, 3)
        XCTAssertEqual(CommandStore.commandSets[0].name, "Imported")
        XCTAssertEqual(CommandStore.commandSets[1].name, "Keep")
        XCTAssertEqual(CommandStore.commandSets[2].name, "New")

        try CommandStore.importDocument(from: importURL, mode: .replace)
        XCTAssertEqual(CommandStore.commandSets.map(\.name), ["Imported", "New"])
    }

    func testSSHKeySetupUsesAskForHostKeyVerification() {
        let connection = SSHConnection(username: "root", host: "example.com", port: nil)
        let command = SSHShellCommand.buildForPasswordAuth(connection: connection, remoteScript: "true")
        XCTAssertTrue(command.contains("StrictHostKeyChecking=ask"))
    }

    func testSSHKeyUsesUserSSHDirectoryInsteadOfAppContainer() {
        XCTAssertTrue(SSHKeySetup.privateKeyURL.path.hasSuffix("/.ssh/commando_ed25519"))
        XCTAssertFalse(SSHKeySetup.privateKeyURL.path.contains("/Library/Containers/"))
    }

    func testExampleCommandSetContent() {
        let example = ExampleCommandSet.helloWorld
        XCTAssertEqual(example.id, ExampleCommandSet.id)
        XCTAssertEqual(example.name, "Hello World")
        XCTAssertEqual(example.nonEmptySteps, ["echo 'Hello, World!'"])
    }

    func testMarkRemovedIfNeededSetsFlag() {
        let key = "exampleCommandSetRemoved"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        ExampleCommandSet.markRemovedIfNeeded(UUID())
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))

        ExampleCommandSet.markRemovedIfNeeded(ExampleCommandSet.id)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }

    func testExampleCommandSetDoesNotReinstallAfterRemoval() {
        let removedKey = "exampleCommandSetRemoved"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let originalOverride = CommandStore.storageDirectoryOverride
        let originalRemoved = UserDefaults.standard.bool(forKey: removedKey)

        CommandStore.storageDirectoryOverride = directory
        CommandStore.resetCache()
        CommandStore.commandSets = []
        UserDefaults.standard.set(true, forKey: removedKey)

        
        defer {
            CommandStore.storageDirectoryOverride = originalOverride
            CommandStore.resetCache()
            UserDefaults.standard.set(originalRemoved, forKey: removedKey)
            try? FileManager.default.removeItem(at: directory)
        }

        ExampleCommandSet.installIfNeeded()

        if CommandStore.commandSets.contains(where: { $0.id == ExampleCommandSet.id }) {
            XCTFail("Example command set should not install after removal flag is set")
        }
    }
}
