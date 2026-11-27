using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Commando.Execution;
using Commando.Licensing;
using Commando.Models;
using Commando.Preferences;
using Commando.Ssh;
using Commando.Storage;
using Commando.Updates;
using Xunit;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace Commando.Tests;

public sealed class CommandoTests
{
    const string PublicKeyBase64 = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=";
    const string CrossLanguageKey =
        "COMMANDO1.eyJlbWFpbCI6InBhdEBleGFtcGxlLmNvbSIsImlkIjoiWlNSOUFXTUZTVzM4IiwiaXNzdWVkIjoxNzI0MTQwODAwLCJuYW1lIjoiUGF0IEV4YW1wbGUiLCJ2IjoxfQ.o-HUPhulTsnFAZmIZ_Dca63GmMMhouxl6veQk7-ZdmrHFdV4a7hszxAnWtb9vNQl9Dlv4WW8cQjNsghNG5WbBg";

    static byte[] PrivateSeed => Enumerable.Range(0, 32).Select(value => (byte)value).ToArray();

    [Fact]
    public void SshConnectionParsesHostWithoutPort()
    {
        var connection = SshConnection.Parse("deploy@example.com");
        Assert.Equal("deploy", connection?.Username);
        Assert.Equal("example.com", connection?.Host);
        Assert.Null(connection?.Port);
    }

    [Fact]
    public void SshConnectionParsesHostWithPort()
    {
        var connection = SshConnection.Parse("deploy@example.com:2222");
        Assert.Equal(2222, connection?.Port);
    }

    [Fact]
    public void SshConnectionRejectsInvalidInput()
    {
        Assert.Null(SshConnection.Parse(""));
        Assert.Null(SshConnection.Parse("not-valid"));
        Assert.Null(SshConnection.Parse("@host"));
    }

    [Fact]
    public void SshConnectionStripsSshPrefix()
    {
        var connection = SshConnection.Parse("ssh admin@256.256.256.256");
        Assert.Equal("admin", connection?.Username);
        Assert.Equal("256.256.256.256", connection?.Host);
    }

    [Fact]
    public void CommandSetDecodesParallelSessions()
    {
        var commandSet = DecodeSet("""{"name":"Stack","sessions":[["cd frontend","npm run dev"],["cd backend","npm start"]]}""");
        Assert.Equal(new[] { "cd frontend", "npm run dev" }, commandSet.Sessions[0].Steps);
        Assert.Equal(new[] { "cd backend", "npm start" }, commandSet.Sessions[1].Steps);
        Assert.Equal(2, commandSet.NonEmptySessions.Count);
        Assert.Equal("2 sessions", commandSet.StepsSummary);
    }

    [Fact]
    public void CommandSetDecodesNamedSessions()
    {
        var commandSet = DecodeSet("""{"name":"Stack","sessions":[{"name":"Frontend","steps":["npm run dev"]},{"name":"Backend","steps":["npm start"]}]}""");
        Assert.Equal(new[] { "Frontend", "Backend" }, commandSet.Sessions.Select(session => session.Name));
        Assert.Equal(new[] { "npm run dev" }, commandSet.Sessions[0].Steps);
    }

    [Fact]
    public void CommandSetLegacyStepsBecomeOneSession()
    {
        var commandSet = DecodeSet("""{"name":"Legacy","commands":["echo hello","echo world"]}""");
        Assert.Equal("Legacy", commandSet.Name);
        Assert.Equal(new[] { "echo hello", "echo world" }, commandSet.NonEmptySteps);
        Assert.Empty(commandSet.ServerDetails);
    }

    [Fact]
    public void CommandSetMigratesDelaySteps()
    {
        var commandSet = DecodeSet("""{"name":"Delay","steps":[{"kind":"delay","text":"5"},{"kind":"command","text":"ls"}]}""");
        Assert.Equal(new[] { "sleep 5", "ls" }, commandSet.NonEmptySteps);
    }

    [Fact]
    public void CommandSetIgnoresBlankLines()
    {
        var commandSet = new CommandSet("Test", steps: new[] { "  echo one  ", "", "echo two" });
        Assert.Equal(new[] { "echo one", "echo two" }, commandSet.NonEmptySteps);
    }

    [Fact]
    public void TerminalCommandsReturnsOneCommandPerSession()
    {
        var commandSet = new CommandSet("Dev", sessions: new[]
        {
            new CommandSession(steps: new[] { "cd frontend", "npm run dev" }),
            new CommandSession(steps: new[] { "cd backend", "npm start" }),
        });
        Assert.Equal(new[] { "cd frontend\nnpm run dev", "cd backend\nnpm start" }, CommandExecutor.TerminalCommands(commandSet));
    }

    [Fact]
    public void TerminalCommandsSshWrapsEachSession()
    {
        var commandSet = new CommandSet("Remote", "root@vultr", sessions: new[]
        {
            new CommandSession(steps: new[] { "uptime" }),
            new CommandSession(steps: new[] { "df -h" }),
        });
        var commands = CommandExecutor.TerminalCommands(commandSet);
        Assert.Equal(2, commands.Count);
        Assert.Contains("root@vultr", commands[0]);
        Assert.Contains("root@vultr", commands[1]);
        Assert.NotEqual(commands[0], commands[1]);
    }

    [Fact]
    public void RemoteScriptKeepsSessionOpen()
    {
        Assert.Equal("set -e\ncd leg/\nexec bash -i </dev/tty", SshShellCommand.RemoteScript(new[] { "cd leg/" }, true));
        Assert.Equal("set -e\ncd leg/\nnpm install", SshShellCommand.RemoteScript(new[] { "cd leg/", "npm install" }, false));
        Assert.Equal("exec bash -i </dev/tty", SshShellCommand.RemoteScript(Array.Empty<string>(), true));
    }

    [Fact]
    public void SshShellCommandBuildsInteractiveCommand()
    {
        var connection = new SshConnection("root", "example.com", null);
        var command = SshShellCommand.Build(connection, "cd leg/\nexec bash -i </dev/tty", interactive: true);
        Assert.Contains(" -t ", command);
        Assert.Contains("mktemp /tmp/commandrunner", command);
        Assert.Contains("base64 -d", command);
        Assert.DoesNotContain("bash -s", command);
    }

    [Fact]
    public void SshPasswordAuthAsksForHostKey()
    {
        var command = SshShellCommand.BuildForPasswordAuth(new SshConnection("root", "example.com", null), "true");
        Assert.Contains("StrictHostKeyChecking=ask", command);
    }

    [Fact]
    public void SshStepParserReadsPortAndRemoteCommand()
    {
        var connection = SshStepParser.ParseBareSshCommand("ssh -p 2222 deploy@example.com uptime");
        Assert.Equal(2222, connection?.Port);
        Assert.Equal("uptime", SshStepParser.RemoteCommand("ssh -p 2222 deploy@example.com uptime"));
        Assert.Null(SshStepParser.RemoteCommand("ssh admin@256.256.256.256"));
    }

    [Fact]
    public void EmptyRemoteCommandSetStillOpensSsh()
    {
        var commandSet = new CommandSet("Server shell", "root@vultr", steps: new[] { "" });
        var command = CommandExecutor.TerminalCommand(commandSet);
        Assert.Contains("ssh ", command);
        Assert.Contains("root@vultr", command);
        Assert.Contains("mktemp /tmp/commandrunner", command);
    }

    [Fact]
    public void WrappedCommandPrintsBannerAndKeepsShellOpen()
    {
        var wrapped = TerminalLauncher.WrappedCommand("cd leg/\nls", "Test Set");
        Assert.Contains("========== Commando ==========", wrapped);
        Assert.Contains("cd leg/", wrapped);
        Assert.Contains("ls", wrapped);
        Assert.Contains("set -e", wrapped);
        Assert.Contains("exec \"$user_shell\" -l", wrapped);
    }

    [Fact]
    public void WrappedCommandIsValidBash()
    {
        var bash = TerminalLauncher.FindBash();
        Assert.False(string.IsNullOrEmpty(bash));
        var local = TerminalLauncher.WrappedCommand("echo 'Hello, World!'\nls", "Hello World");
        var remote = CommandExecutor.TerminalCommands(new CommandSet("Remote", "root@example.com", steps: new[] { "uptime" }))[0];
        var wrappedRemote = TerminalLauncher.WrappedCommand(remote, "Remote");
        Assert.Equal(0, BashSyntax(bash!, local));
        Assert.Equal(0, BashSyntax(bash!, wrappedRemote));
    }

    static int BashSyntax(string bash, string body)
    {
        var path = Path.Combine(Path.GetTempPath(), "commando-syntax-" + Guid.NewGuid().ToString("N") + ".sh");
        File.WriteAllText(path, "#!/bin/bash\n" + body.Replace("\r\n", "\n") + "\n");
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = bash,
                ArgumentList = { "-n", path },
                RedirectStandardError = true,
                UseShellExecute = false,
            });
            Assert.NotNull(process);
            process!.WaitForExit(10000);
            var error = process.StandardError.ReadToEnd();
            Assert.True(process.ExitCode == 0, error);
            return process.ExitCode;
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void PaneTitleUsesSessionName()
    {
        Assert.Equal("Parallel test (2)", TerminalLauncher.PaneTitle("Parallel test", "", 1, 2));
        Assert.Equal("Parallel test (Frontend)", TerminalLauncher.PaneTitle("Parallel test", "Frontend", 1, 2));
        Assert.Equal("Parallel test", TerminalLauncher.PaneTitle("Parallel test", "", 0, 1));
    }

    [Fact]
    public void WarpTabConfigSplitsParallelSessions()
    {
        var single = TerminalLauncher.WarpTabConfigToml("Solo", @"C:\Users\test", new[] { "bash run.sh" });
        Assert.Contains("id = \"main\"", single);
        Assert.DoesNotContain("split = \"horizontal\"", single);

        var parallel = TerminalLauncher.WarpTabConfigToml("Stack", @"C:\Users\test", new[] { "cmd1", "cmd2" });
        Assert.Contains("split = \"horizontal\"", parallel);
        Assert.Contains("children = [\"p0\", \"p1\"]", parallel);
        Assert.Contains("id = \"p0\"", parallel);
        Assert.Contains("id = \"p1\"", parallel);
    }

    [Fact]
    public void DocumentRoundTripAndVersionGate()
    {
        var encoded = CommandSetDocument.Encode(new[] { new CommandSet("Dev", steps: new[] { "echo hi" }) });
        var payload = CommandSetDocument.DecodePayload(encoded);
        Assert.Equal(1, payload.Version);
        Assert.Equal("Dev", payload.CommandSets[0].Name);
        Assert.Equal(new[] { "echo hi" }, payload.CommandSets[0].NonEmptySteps);

        var newer = Encoding.UTF8.GetBytes("""{"version":99,"commandSets":[]}""");
        var error = Assert.Throws<CommandSetDocument.DocumentException>(() => CommandSetDocument.Decode(newer));
        Assert.Contains("99", error.Message);

        var legacy = CommandSetDocument.Decode(Encoding.UTF8.GetBytes("""[{"name":"Legacy","steps":["echo hello"]}]"""));
        Assert.Equal("Legacy", legacy[0].Name);
    }

    [Fact]
    public void DocumentMergesById()
    {
        var shared = Guid.NewGuid();
        var merged = CommandSetDocument.Merge(
            new[]
            {
                new CommandSet("Local", steps: new[] { "echo local" }, id: shared),
                new CommandSet("Only Local", steps: new[] { "echo a" }),
            },
            new[]
            {
                new CommandSet("Imported", steps: new[] { "echo imported" }, id: shared),
                new CommandSet("Only Imported", steps: new[] { "echo b" }),
            });
        Assert.Equal(3, merged.Count);
        Assert.Equal(shared, merged[0].Id);
        Assert.Equal("Imported", merged[0].Name);
        Assert.Equal("Only Local", merged[1].Name);
        Assert.Equal("Only Imported", merged[2].Name);
    }

    [Fact]
    public void EncryptedBlobRoundTrips()
    {
        SecureDataStore.KeyOverride = RandomNumberGenerator.GetBytes(32);
        try
        {
            var sample = new[] { new CommandSet("Secure", "user@example.com", steps: new[] { "echo hi" }) };
            var encrypted = SecureDataStore.Encrypt(CommandSetDocument.Encode(sample));
            var loaded = CommandSetDocument.DecodeStoredData(encrypted);
            Assert.Equal("Secure", loaded[0].Name);
            Assert.Equal("user@example.com", loaded[0].ServerDetails);
        }
        finally
        {
            SecureDataStore.KeyOverride = null;
        }
    }

    [Fact]
    public void CommandSetsRoundTripThroughJsonFile()
    {
        using var temp = new TempApp();
        CommandStore.CommandSets = new List<CommandSet> { new("Secure", "user@example.com", steps: new[] { "echo hi" }) };
        CommandStore.ResetCache();
        var loaded = CommandStore.CommandSets;
        Assert.Equal("Secure", loaded[0].Name);
        Assert.True(File.Exists(Path.Combine(temp.Directory, "command-sets.json")));
    }

    [Fact]
    public void CloudSyncErrorNamesOneDrive()
    {
        Assert.Contains("OneDrive is not available", CommandStore.StoreException.OneDriveUnavailable.Message);
        Assert.DoesNotContain("iCloud", CommandStore.StoreException.OneDriveUnavailable.Message);
    }

    [Fact]
    public void LegacyICloudSyncPreferenceStillEnablesOneDriveSync()
    {
        using var temp = new TempApp();
        File.WriteAllText(Commando.Storage.Preferences.FilePath, """
        {
          "syncCommandSetsViaiCloud": true
        }
        """);
        Commando.Storage.Preferences.ResetCache();
        Assert.True(Commando.Storage.Preferences.OneDriveSyncEnabled);
    }

    [Fact]
    public void ImportMergeAndReplace()
    {
        using var temp = new TempApp();
        ActivateLicense();
        LicenseRemoteCheck.ResponseOverride = new LicenseRemoteCheck.RemoteResult(false, true);
        LicenseStatus.Register("Pat Example", "pat@example.com", LicenseKey.Generate("Pat Example", "pat@example.com", PrivateSeed, 1_724_140_800));
        var shared = Guid.NewGuid();
        CommandStore.CommandSets = new List<CommandSet>
        {
            new("Local", steps: new[] { "echo local" }, id: shared),
            new("Keep", steps: new[] { "echo keep" }),
        };
        var importPath = Path.Combine(temp.Directory, "import.json");
        File.WriteAllBytes(importPath, CommandSetDocument.Encode(new[]
        {
            new CommandSet("Imported", steps: new[] { "echo imported" }, id: shared),
            new CommandSet("New", steps: new[] { "echo new" }),
        }));
        CommandStore.ImportDocument(importPath, CommandStore.ImportMode.Merge);
        Assert.Equal(new[] { "Imported", "Keep", "New" }, CommandStore.CommandSets.Select(set => set.Name));
        CommandStore.ImportDocument(importPath, CommandStore.ImportMode.Replace);
        Assert.Equal(new[] { "Imported", "New" }, CommandStore.CommandSets.Select(set => set.Name));
    }

    [Fact]
    public void ExampleCommandSetDoesNotReinstallAfterRemoval()
    {
        using var temp = new TempApp();
        CommandStore.CommandSets = new List<CommandSet>();
        ExampleCommandSet.MarkRemovedIfNeeded(ExampleCommandSet.Id);
        ExampleCommandSet.InstallIfNeeded();
        Assert.DoesNotContain(CommandStore.CommandSets, set => set.Id == ExampleCommandSet.Id);
    }

    [Fact]
    public void ExampleCommandSetContent()
    {
        var example = ExampleCommandSet.HelloWorld;
        Assert.Equal(ExampleCommandSet.Id, example.Id);
        Assert.Equal("Hello World", example.Name);
        Assert.Equal(new[] { "echo 'Hello, World!'" }, example.NonEmptySteps);
    }

    [Fact]
    public void SshKeyLivesInUserSshDirectory()
    {
        Assert.EndsWith(Path.Combine(".ssh", "commando_ed25519"), SshKeySetup.PrivateKeyPath);
        Assert.DoesNotContain("Application Support", SshKeySetup.PrivateKeyPath);
    }

    [Fact]
    public void TerminalDefaultPathExists()
    {
        Assert.True(File.Exists(TerminalAppSettings.DefaultPath));
        Assert.False(string.IsNullOrEmpty(TerminalAppSettings.DisplayName(TerminalAppSettings.DefaultPath)));
    }

    [Fact]
    public void WarpConfigRequiresExactDirectory()
    {
        var app = Path.Combine("C:", "Program Files", "Warp", "Warp.exe");
        var expected = WarpConfigAccess.DefaultConfigDirectory(app);
        Assert.True(WarpConfigAccess.IsExpectedConfigDirectory(expected, app));
        Assert.False(WarpConfigAccess.IsExpectedConfigDirectory(Path.GetDirectoryName(expected)!, app));
        Assert.Equal(".warp-preview", WarpConfigAccess.ConfigDirectoryName(Path.Combine("C:", "WarpPreview.exe")));
    }

    [Fact]
    public void UpdateCheckerComparesVersionsAndUrls()
    {
        Assert.True(UpdateChecker.IsVersion("2.1", "1.0"));
        Assert.False(UpdateChecker.IsVersion("1.0", "2.1"));
        Assert.False(UpdateChecker.IsVersion("1.0", "1.0"));
        var direct = new Uri("https://files.mac-attic.com/commando.dmg");
        var http = new Uri("http://files.mac-attic.com/commando.dmg");
        Assert.Equal(direct, UpdateChecker.UpdateUrl(direct));
        Assert.Equal("https", UpdateChecker.UpdateUrl(http)?.Scheme);
        Assert.Null(UpdateChecker.UpdateUrl(new Uri("https://evil.example/phish")));
        Assert.False(UpdateChecker.IsAllowedUpdateUrl(new Uri("file:///tmp/evil")));
        Assert.Equal("Download", UpdateChecker.UpdateActionTitle());
    }

    [Fact]
    public void UpdateInfoParserReadsMinimumVersion()
    {
        var xml = """
            <updateInfo>
              <currentMacOS>2.0.0</currentMacOS>
              <minimumVersionAllowed>1.5.0</minimumVersionAllowed>
              <macOSUrl>https://files.mac-attic.com/commando.dmg</macOSUrl>
            </updateInfo>
            """;
        var info = UpdateInfoParser.Parse(Encoding.UTF8.GetBytes(xml));
        Assert.Equal("1.5.0", info?.MinimumVersionAllowed);
        Assert.Equal("2.0.0", info?.CurrentMacOs);
    }

    [Fact]
    public void MinimumVersionLocksApp()
    {
        AppLock.Clear();
        try
        {
            UpdateChecker.EnforceMinimumVersionIfNeeded(new UpdateInfo
            {
                CurrentMacOs = "2.0.0",
                CurrentMacOsChangeLog = "Required update",
                MacOsUrl = new Uri("https://files.mac-attic.com/commando.dmg"),
                MinimumVersionAllowed = "9.0.0",
            });
            Assert.True(AppLock.IsLocked);
        }
        finally
        {
            AppLock.Clear();
        }
    }

    [Fact]
    public void LicenseKeyAcceptsCrossLanguageVector()
    {
        ActivateLicense();
        var generated = LicenseKey.Generate("Pat Example", "pat@example.com", PrivateSeed, 1_724_140_800);
        Assert.StartsWith("COMMANDO1.", generated);
        Assert.True(LicenseKey.IsValid("Pat Example", "pat@example.com", generated));
        Assert.True(LicenseKey.IsValid("  Pat   Example  ", "Pat@Example.com", generated));
        Assert.True(LicenseKey.IsValid("Pat Example", "pat@example.com", CrossLanguageKey));
        Assert.False(LicenseKey.IsValid("Pat Example", "pat@example.com", "AAAAA-BBBBB-CCCCC-DDDDD"));
        Assert.False(LicenseKey.IsValid("Pat Example", "other@example.com", generated));
        Assert.Equal(12, LicenseKey.BanToken(generated).Length);
        Assert.Equal("ZSR9AWMFSW38", LicenseKey.BanToken(CrossLanguageKey));
    }

    [Fact]
    public void LicenseRemoteCheckParsesBodyAndUrl()
    {
        Assert.True(LicenseRemoteCheck.ParseResponse(Encoding.UTF8.GetBytes("{\"banned\":true,\"ok\":true}"))?.Banned);
        Assert.False(LicenseRemoteCheck.ParseResponse(Encoding.UTF8.GetBytes("{\"banned\":false,\"ok\":true}"))?.Banned);
        Assert.Null(LicenseRemoteCheck.ParseResponse(Encoding.UTF8.GetBytes("not-json")));
        Assert.Null(LicenseRemoteCheck.ParseResponse(Encoding.UTF8.GetBytes("{}")));
        var url = LicenseRemoteCheck.RequestUrl("ABCDEF123456", "1.0.0", "activation");
        Assert.Equal("proxy.manticore.nz", url?.Host);
        Assert.Contains("token=ABCDEF123456", url?.Query);
    }

    [Fact]
    public void RegisterPersistsAndClearRemoves()
    {
        using var temp = new TempApp();
        ActivateLicense();
        LicenseRemoteCheck.ResponseOverride = new LicenseRemoteCheck.RemoteResult(false, true);
        Assert.False(LicenseStatus.IsUnlocked);
        var key = LicenseKey.Generate("Pat Example", "pat@example.com", PrivateSeed);
        LicenseStatus.Register("Pat Example", "pat@example.com", key);
        var stored = File.ReadAllBytes(LicenseStatus.RegistrationFilePath);
        Assert.True(stored.AsSpan().IndexOf(Encoding.UTF8.GetBytes("pat@example.com")) < 0);
        Assert.True(LicenseStatus.IsUnlocked);
        Assert.Equal("Registered to: Pat Example", LicenseStatus.RegisteredLine);
        Assert.Throws<RegistrationException>(() => LicenseStatus.Register("Pat Example", "pat@example.com", "nope"));
        LicenseStatus.Clear();
        Assert.False(File.Exists(LicenseStatus.RegistrationFilePath));
        Assert.False(LicenseStatus.IsUnlocked);
        Assert.Null(LicenseStatus.RegisteredLine);
    }

    [Fact]
    public void RegisterRejectsBannedKey()
    {
        using var _ = new TempApp();
        ActivateLicense();
        LicenseRemoteCheck.ResponseOverride = new LicenseRemoteCheck.RemoteResult(true, true);
        var error = Assert.Throws<RegistrationException>(() =>
            LicenseStatus.Register("Pat Example", "pat@example.com", LicenseKey.Generate("Pat Example", "pat@example.com", PrivateSeed)));
        Assert.Equal(RegistrationErrorKind.Revoked, error.Kind);
        Assert.False(File.Exists(LicenseStatus.RegistrationFilePath));
        Assert.False(LicenseStatus.IsUnlocked);
    }

    [Fact]
    public void CachedRevocationPersistsOffline()
    {
        using var _ = new TempApp();
        ActivateLicense();
        LicenseRemoteCheck.ResponseOverride = new LicenseRemoteCheck.RemoteResult(false, true);
        LicenseStatus.Register("Pat Example", "pat@example.com", LicenseKey.Generate("Pat Example", "pat@example.com", PrivateSeed));
        LicenseRemoteCheck.ResponseOverride = new LicenseRemoteCheck.RemoteResult(true, true);
        LicenseStatus.RefreshRemoteStatus();
        var start = DateTime.UtcNow;
        while (!LicenseStatus.IsRevoked && DateTime.UtcNow - start < TimeSpan.FromSeconds(2))
        {
            Thread.Sleep(50);
        }

        Assert.True(LicenseStatus.IsRevoked);
        LicenseRemoteCheck.ResponseOverride = null;
        LicenseRemoteCheck.SkipNetwork = true;
        LicenseStatus.HydrateFromStorage();
        Assert.True(LicenseStatus.IsRevoked);
    }

    [Fact]
    public void RevokedLicenseKeepsFreeRunOfFirstSetOnly()
    {
        using var _ = new TempApp();
        ActivateLicense();
        LicenseStatus.IsRevokedOverride = true;
        var first = new CommandSet("One", steps: new[] { "echo 1" });
        var second = new CommandSet("Two", steps: new[] { "echo 2" });
        CommandStore.CommandSets = new List<CommandSet> { first, second };
        Assert.Equal(
            "This license has been revoked. Please get in touch with Manticore SW for more information.",
            RegistrationException.MessageFor(RegistrationErrorKind.Revoked));
        var add = Assert.Throws<RegistrationException>(() => LicenseStatus.EnsureCanAddCommandSet(2));
        Assert.Equal(RegistrationErrorKind.Revoked, add.Kind);
        LicenseStatus.EnsureCanRun(first);
        var run = Assert.Throws<RegistrationException>(() => LicenseStatus.EnsureCanRun(second));
        Assert.Equal(RegistrationErrorKind.Revoked, run.Kind);
        var parallel = new CommandSet("Multi", sessions: new[]
        {
            new CommandSession("A", new[] { "echo 1" }),
            new CommandSession("B", new[] { "echo 2" }),
        });
        CommandStore.CommandSets = new List<CommandSet> { parallel };
        Assert.Equal(RegistrationErrorKind.Revoked, Assert.Throws<RegistrationException>(() => LicenseStatus.EnsureCanRun(parallel)).Kind);
    }

    [Fact]
    public void UnregisteredLicenseCanUseFreeAllowances()
    {
        using var _ = new TempApp();
        ActivateLicense();
        var first = new CommandSet("One", steps: new[] { "echo 1" });
        var second = new CommandSet("Two", steps: new[] { "echo 2" });
        var parallel = new CommandSet("Parallel", sessions: new[]
        {
            new CommandSession("A", new[] { "echo 1" }),
            new CommandSession("B", new[] { "echo 2" }),
        });
        CommandStore.CommandSets = new List<CommandSet> { first, second };
        LicenseStatus.Clear();
        Assert.False(LicenseStatus.IsRevoked);
        Assert.False(LicenseStatus.IsUnlocked);
        LicenseStatus.EnsureCanAddCommandSet(0);
        LicenseStatus.EnsureCanRun(first);
        Assert.Equal(RegistrationErrorKind.RegistrationRequired, Assert.Throws<RegistrationException>(() => LicenseStatus.EnsureCanRun(second)).Kind);
        CommandStore.CommandSets = new List<CommandSet> { parallel };
        Assert.Equal(RegistrationErrorKind.RegistrationRequired, Assert.Throws<RegistrationException>(() => LicenseStatus.EnsureCanRun(parallel)).Kind);
    }

    [Fact]
    public void UnregisteredImportOfSeveralSetsIsBlocked()
    {
        using var temp = new TempApp();
        ActivateLicense();
        CommandStore.CommandSets = new List<CommandSet> { new("One", steps: new[] { "echo 1" }) };
        var importPath = Path.Combine(temp.Directory, "import.json");
        File.WriteAllBytes(importPath, CommandSetDocument.Encode(new[]
        {
            new CommandSet("Two", steps: new[] { "echo 2" }),
            new CommandSet("Three", steps: new[] { "echo 3" }),
        }));
        var error = Assert.Throws<RegistrationException>(() => CommandStore.ImportDocument(importPath, CommandStore.ImportMode.Replace));
        Assert.Equal(RegistrationErrorKind.RegistrationRequired, error.Kind);
    }

    [Fact]
    public void TamperedSentinelBlocksPaidFeatures()
    {
        LicenseGuard.SkipIntegrityChecks = true;
        LicenseGuard.IntegrityIssueOverride = LicenseGuard.IntegrityIssue.TamperedSentinel;
        try
        {
            Assert.False(LicenseGuard.Permits(LicenseGuard.Feature.Run));
        }
        finally
        {
            LicenseGuard.IntegrityIssueOverride = null;
            LicenseGuard.SkipIntegrityChecks = true;
        }
    }

    static CommandSet DecodeSet(string json) =>
        CommandSetDocument.Decode(Encoding.UTF8.GetBytes("[" + json + "]"))[0];

    static void ActivateLicense()
    {
        LicenseStatus.ResetSessionState();
        LicenseKey.PublicKeyOverride = Convert.FromBase64String(PublicKeyBase64);
        RegistrationKeychain.KeyOverride = RandomNumberGenerator.GetBytes(32);
        LicenseGuard.SkipIntegrityChecks = true;
        LicenseRemoteCheck.SkipNetwork = true;
        AppLock.Clear();
        AppLock.ReasonOverride = null;
    }

    sealed class TempApp : IDisposable
    {
        public string Directory { get; } = Path.Combine(Path.GetTempPath(), "commando-tests", Guid.NewGuid().ToString("N"));

        public TempApp()
        {
            System.IO.Directory.CreateDirectory(Directory);
            CommandStore.StorageDirectoryOverride = Directory;
            CommandStore.ResetCache();
            LicenseStatus.StorageDirectoryOverride = Directory;
            LicenseGuard.StorageDirectoryOverride = Directory;
            Commando.Storage.Preferences.FileOverride = Path.Combine(Directory, "preferences.json");
            Commando.Storage.Preferences.ResetCache();
            LicenseStatus.ResetSessionState();
            LicenseStatus.IsRevokedOverride = null;
            LicenseGuard.SkipIntegrityChecks = true;
            LicenseGuard.IntegrityIssueOverride = null;
            LicenseRemoteCheck.SkipNetwork = true;
            LicenseRemoteCheck.ResponseOverride = null;
            RegistrationKeychain.KeyOverride = RandomNumberGenerator.GetBytes(32);
            AppLock.Clear();
        }

        public void Dispose()
        {
            CommandStore.StorageDirectoryOverride = null;
            CommandStore.ResetCache();
            LicenseStatus.StorageDirectoryOverride = null;
            LicenseStatus.IsRevokedOverride = null;
            LicenseStatus.ResetSessionState();
            LicenseGuard.StorageDirectoryOverride = null;
            LicenseGuard.IntegrityIssueOverride = null;
            LicenseRemoteCheck.ResponseOverride = null;
            LicenseRemoteCheck.SkipNetwork = true;
            Commando.Storage.Preferences.FileOverride = null;
            Commando.Storage.Preferences.ResetCache();
            RegistrationKeychain.KeyOverride = null;
            AppLock.Clear();
            AppLock.ReasonOverride = null;
            try
            {
                System.IO.Directory.Delete(Directory, true);
            }
            catch
            {
                // Temporary files can remain locked for a moment on a network profile.
            }
        }
    }
}
