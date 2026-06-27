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

    func testCommandSetDecodesLegacyCommandsKey() throws {
        let json = """
        {"id":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","name":"Legacy","commands":["echo hello","echo world"]}
        """.data(using: .utf8)!

        let commandSet = try JSONDecoder().decode(CommandSet.self, from: json)
        XCTAssertEqual(commandSet.name, "Legacy")
        XCTAssertEqual(commandSet.nonEmptySteps, ["echo hello", "echo world"])
        XCTAssertTrue(commandSet.serverDetails.isEmpty)
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

    func testTerminalLauncherUsesStableScriptPath() {
        let url = TerminalLauncher.scriptURL
        XCTAssertTrue(url.path.contains("Application Support/Commando/run.command"))
    }

    func testTerminalLauncherWrapsCommandWithLoginShell() {
        let wrapped = TerminalLauncher.wrappedCommand("cd leg/\nls", commandSetName: "Test Set")
        XCTAssertTrue(wrapped.contains("user_shell=\"${SHELL:-/bin/zsh}\""))
        XCTAssertTrue(wrapped.contains("Running %s"))
        XCTAssertTrue(wrapped.contains("cd leg/"))
        XCTAssertTrue(wrapped.contains("ls"))
        XCTAssertTrue(wrapped.contains("exec \"$user_shell\" -l"))
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
        UserDefaults.standard.set(true, forKey: removedKey)
        defer { UserDefaults.standard.removeObject(forKey: removedKey) }

        ExampleCommandSet.installIfNeeded()

        if UserDefaults.standard.commandSets.contains(where: { $0.id == ExampleCommandSet.id }) {
            XCTFail("Example command set should not install after removal flag is set")
        }
    }
}
