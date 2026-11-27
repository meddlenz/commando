using System.Diagnostics;
using System.Text;
using Commando.Preferences;
using Commando.Storage;

namespace Commando.Execution;

public static class TerminalLauncher
{
    public sealed class LaunchException : Exception
    {
        public LaunchException(string message) : base(message)
        {
        }
    }

    enum TerminalKind
    {
        WindowsTerminal,
        Warp,
        Ghostty,
        WezTerm,
        Alacritty,
        CommandPrompt,
        PowerShell,
        Generic,
    }

    public static void Open(string command, string commandSetName, string appPath) =>
        Open(new[] { command }, commandSetName, Array.Empty<string>(), appPath);

    public static void Open(IReadOnlyList<string> commands, string commandSetName, IReadOnlyList<string> sessionNames, string appPath)
    {
        if (commands.Count == 0)
        {
            return;
        }

        if (!File.Exists(appPath))
        {
            throw new LaunchException("Terminal app not found at " + appPath + ".");
        }

        var appName = TerminalAppSettings.DisplayName(appPath);
        var kind = KindFor(appPath);
        var useBash = FindBash() != null;
        var scripts = new List<string>();
        for (var index = 0; index < commands.Count; index++)
        {
            var sessionName = index < sessionNames.Count ? sessionNames[index] : "";
            var title = PaneTitle(commandSetName, sessionName, index, commands.Count);
            scripts.Add(useBash
                ? WrappedCommand(commands[index], title)
                : PowerShellWrappedCommand(commands[index], title));
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        switch (kind)
        {
            case TerminalKind.WindowsTerminal:
                RunInWindowsTerminal(scripts, commandSetName, sessionNames, appPath);
                break;
            case TerminalKind.Warp:
                RunInWarp(scripts, commandSetName, appPath, home);
                break;
            case TerminalKind.WezTerm:
                RunSeparate(scripts, appPath, appName, script => new[] { "start", "--", BashOrPowerShell(script), script });
                break;
            case TerminalKind.Alacritty:
            case TerminalKind.Ghostty:
                RunSeparate(scripts, appPath, appName, script => new[] { "-e", BashOrPowerShell(script), script });
                break;
            case TerminalKind.CommandPrompt:
                RunInCommandPrompt(scripts, appPath);
                break;
            case TerminalKind.PowerShell:
                RunSeparate(scripts, appPath, appName, script => new[] { "-NoExit", "-File", script }, waitForStart: false);
                break;
            default:
                RunSeparate(scripts, appPath, appName, script => new[] { "-e", BashOrPowerShell(script), script });
                break;
        }
    }

    public static string WrappedCommand(string command, string commandSetName)
    {
        var title = commandSetName.Trim();
        var safeTitle = title.Length == 0 ? "Command Set" : title;
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).Replace('\\', '/');
        return string.Join("\n", new[]
        {
            "user_home=" + ShellSingleQuote(home),
            "if [ -d \"$user_home\" ]; then",
            "    export HOME=\"$user_home\"",
            "    cd \"$user_home\"",
            "fi",
            "",
            "user_shell=\"${SHELL:-}\"",
            "if [ -z \"$user_shell\" ] || [ ! -x \"$user_shell\" ]; then",
            "    user_shell=\"/usr/bin/bash\"",
            "fi",
            "",
            "shell_path=\"$($user_shell -lic 'printf \"%s\" \"$PATH\"' 2>/dev/null || true)\"",
            "if [ -n \"$shell_path\" ]; then",
            "    export PATH=\"$shell_path\"",
            "fi",
            "",
            "clear 2>/dev/null || printf '\\033c'",
            "",
            "command_set_name=" + ShellSingleQuote(safeTitle),
            "printf '\\n========== Commando ==========\\nRunning %s\\n==============================\\n\\n' \"$command_set_name\"",
            "",
            "{",
            "set -e",
            command,
            "}",
            "status=$?",
            "set +e",
            "",
            "if [ \"$status\" -ne 0 ]; then",
            "    printf '\\nCommando command exited with status %s.\\n' \"$status\"",
            "fi",
            "",
            "exec \"$user_shell\" -l",
        });
    }

    public static string PowerShellWrappedCommand(string command, string commandSetName)
    {
        var title = commandSetName.Trim();
        var safeTitle = title.Length == 0 ? "Command Set" : title;
        var builder = new StringBuilder();
        builder.AppendLine("Set-Location -LiteralPath $env:USERPROFILE");
        builder.AppendLine("Clear-Host");
        builder.AppendLine("Write-Host ''");
        builder.AppendLine("Write-Host '========== Commando =========='");
        builder.AppendLine("Write-Host " + PowerShellQuote("Running " + safeTitle));
        builder.AppendLine("Write-Host '=============================='");
        builder.AppendLine("Write-Host ''");
        builder.AppendLine("$status = 0");
        foreach (var line in command.Replace("\r\n", "\n").Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            builder.AppendLine("Invoke-Expression " + PowerShellQuote(line));
            builder.AppendLine("if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { $status = $LASTEXITCODE; break }");
        }

        builder.AppendLine("if ($status -ne 0) {");
        builder.AppendLine("    Write-Host ''");
        builder.AppendLine("    Write-Host \"Commando command exited with status $status.\"");
        builder.AppendLine("}");
        return builder.ToString();
    }

    public static string PaneTitle(string commandSetName, string sessionName, int index, int count)
    {
        var setName = commandSetName.Trim();
        var safeSet = setName.Length == 0 ? "Command Set" : setName;
        var custom = sessionName.Trim();
        if (custom.Length > 0)
        {
            return safeSet + " (" + custom + ")";
        }

        if (count == 1)
        {
            return safeSet;
        }

        return safeSet + " (" + (index + 1) + ")";
    }

    public static string WarpTabConfigToml(string title, string workingDirectory, IReadOnlyList<string> paneCommands)
    {
        var lines = new List<string>
        {
            "name = \"Commando\"",
            "title = " + TomlDoubleQuoted(title),
            "color = \"blue\"",
            "",
        };

        if (paneCommands.Count == 1)
        {
            lines.AddRange(new[]
            {
                "[[panes]]",
                "id = \"main\"",
                "type = \"terminal\"",
                "directory = " + TomlDoubleQuoted(workingDirectory),
                "commands = [" + TomlDoubleQuoted(paneCommands[0]) + "]",
                "is_focused = true",
            });
            return string.Join("\n", lines);
        }

        var ids = paneCommands.Select((_, index) => "p" + index).ToList();
        lines.AddRange(new[]
        {
            "[[panes]]",
            "id = \"root\"",
            "split = \"horizontal\"",
            "children = [" + string.Join(", ", ids.Select(TomlDoubleQuoted)) + "]",
            "",
        });

        for (var index = 0; index < paneCommands.Count; index++)
        {
            lines.Add("[[panes]]");
            lines.Add("id = " + TomlDoubleQuoted(ids[index]));
            lines.Add("type = \"terminal\"");
            lines.Add("directory = " + TomlDoubleQuoted(workingDirectory));
            lines.Add("commands = [" + TomlDoubleQuoted(paneCommands[index]) + "]");
            if (index == 0)
            {
                lines.Add("is_focused = true");
            }

            lines.Add("");
        }

        return string.Join("\n", lines);
    }

    public static string? FindBash()
    {
        var candidates = new List<string>
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "bin", "bash.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "usr", "bin", "bash.exe"),
        };
        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (!string.IsNullOrEmpty(programFilesX86))
        {
            candidates.Add(Path.Combine(programFilesX86, "Git", "bin", "bash.exe"));
        }

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path))
        {
            return null;
        }

        foreach (var directory in path.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(directory.Trim(), "bash.exe");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch (ArgumentException)
            {
                // Ignore malformed PATH entries.
            }
        }

        return null;
    }

    static void RunInWindowsTerminal(IReadOnlyList<string> commandScripts, string commandSetName, IReadOnlyList<string> sessionNames, string appPath)
    {
        var runs = commandScripts.Select(script => WriteRun(script)).ToList();
        var parts = new List<string> { "-w", "new" };
        for (var index = 0; index < runs.Count; index++)
        {
            if (index > 0)
            {
                parts.Add(";");
            }

            var sessionName = index < sessionNames.Count ? sessionNames[index] : "";
            var title = PaneTitle(commandSetName, sessionName, index, runs.Count);
            var shell = BashOrPowerShell(runs[index].ScriptPath);
            parts.Add("new-tab");
            parts.Add("--title");
            parts.Add(Quote(title));
            parts.Add("--");
            parts.Add(Quote(shell));
            if (shell.EndsWith("powershell.exe", StringComparison.OrdinalIgnoreCase))
            {
                parts.Add("-NoExit");
                parts.Add("-File");
            }

            parts.Add(Quote(runs[index].ScriptPath));
        }

        Start(appPath, string.Join(" ", parts));
    }

    static void RunInWarp(IReadOnlyList<string> commandScripts, string commandSetName, string appPath, string home)
    {
        var title = commandSetName.Trim();
        if (title.Length == 0)
        {
            title = "Commando";
        }

        var wasRunning = Process.GetProcessesByName("Warp").Length > 0;
        var root = WarpConfigAccess.DefaultConfigDirectory(appPath);
        if (!Directory.Exists(root))
        {
            throw new LaunchException(
                "Commando needs access to your Warp configuration folder to open command sets in Warp. You can grant access when prompted, or choose another terminal app in Settings.");
        }

        var runRoot = Path.Combine(root, "commando-runs");
        var paneCommands = commandScripts.Select(script =>
        {
            var run = WriteRun(script, runRoot);
            return ScriptLauncherCommand(run.ScriptPath);
        }).ToList();

        var tabDirectory = Path.Combine(root, "tab_configs");
        var tabConfig = Path.Combine(tabDirectory, "commando.toml");
        var toml = WarpTabConfigToml(title, home, paneCommands);
        try
        {
            Directory.CreateDirectory(tabDirectory);
            File.WriteAllText(tabConfig, toml.Replace("\r\n", "\n"), new UTF8Encoding(false));
        }
        catch (Exception ex)
        {
            throw new LaunchException("Failed to write Warp tab config at " + tabConfig + ": " + ex.Message);
        }

        var scheme = WarpConfigAccess.UrlScheme(appPath);
        var newWindow = wasRunning ? "true" : "false";
        var url = scheme + "://tab_config/commando?new_window=" + newWindow;
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            throw new LaunchException("Failed to open Warp: " + ex.Message);
        }
    }

    static void RunInCommandPrompt(IReadOnlyList<string> commandScripts, string appPath)
    {
        foreach (var script in commandScripts)
        {
            var run = WriteRun(script);
            var shell = BashOrPowerShell(run.ScriptPath);
            Start(appPath, "/k \"" + shell + "\" \"" + run.ScriptPath + "\"");
        }
    }

    static void RunSeparate(
        IReadOnlyList<string> commandScripts,
        string appPath,
        string appName,
        Func<string, string[]> argumentsFor,
        bool waitForStart = true)
    {
        foreach (var script in commandScripts)
        {
            var run = WriteRun(script);
            var arguments = argumentsFor(run.ScriptPath);
            try
            {
                Start(appPath, JoinArguments(arguments));
            }
            catch (Exception ex)
            {
                throw new LaunchException(
                    "Commando tried to run this command in "
                    + appName
                    + " which didn't work. Commando officially supports "
                    + string.Join(", ", TerminalAppSettings.SupportedTerminalNames)
                    + ". \n\nUnderlying error: "
                    + ex.Message);
            }

            if (waitForStart && !WaitForStart(run.StartedPath))
            {
                throw new LaunchException(appName + " opened, but Windows did not pass Commando's command arguments to it.");
            }
        }
    }

    static string BashOrPowerShell(string scriptPath) =>
        scriptPath.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)
            ? Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
            : FindBash() ?? Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");

    static TerminalKind KindFor(string appPath)
    {
        var file = Path.GetFileName(appPath).ToLowerInvariant();
        var display = TerminalAppSettings.DisplayName(appPath).ToLowerInvariant();
        var combined = file + " " + display + " " + appPath.ToLowerInvariant();
        if (file == "wt.exe" || display == "windows terminal" || combined.Contains("windowsterminal"))
        {
            return TerminalKind.WindowsTerminal;
        }

        if (combined.Contains("warp"))
        {
            return TerminalKind.Warp;
        }

        if (combined.Contains("ghostty"))
        {
            return TerminalKind.Ghostty;
        }

        if (combined.Contains("wezterm") || combined.Contains("wez.wezterm") || combined.Contains("wezfurlong"))
        {
            return TerminalKind.WezTerm;
        }

        if (combined.Contains("alacritty"))
        {
            return TerminalKind.Alacritty;
        }

        if (file is "cmd.exe" or "command.com")
        {
            return TerminalKind.CommandPrompt;
        }

        if (file is "powershell.exe" or "pwsh.exe")
        {
            return TerminalKind.PowerShell;
        }

        return TerminalKind.Generic;
    }

    sealed class SharedRun
    {
        public SharedRun(string scriptPath, string startedPath)
        {
            ScriptPath = scriptPath;
            StartedPath = startedPath;
        }

        public string ScriptPath { get; }
        public string StartedPath { get; }
    }

    static SharedRun WriteRun(string commandScript, string? root = null)
    {
        var bash = FindBash();
        var useBash = bash != null;
        root ??= AppStoragePaths.TerminalRunsDirectory;
        CleanupOldRuns(root);
        var directory = Path.Combine(root, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var scriptPath = Path.Combine(directory, useBash ? "run.sh" : "run.ps1");
        var startedPath = Path.Combine(directory, "started");
        string script;
        if (useBash)
        {
            var started = startedPath.Replace('\\', '/');
            script = "#!/bin/bash\ntouch " + ShellSingleQuote(started) + " 2>/dev/null || true\n" + commandScript + "\n";
        }
        else
        {
            script = "New-Item -ItemType File -Force -Path " + Quote(startedPath) + " | Out-Null\r\n" + commandScript + "\r\n";
        }

        File.WriteAllText(scriptPath, script.Replace("\r\n", useBash ? "\n" : "\r\n"), new UTF8Encoding(false));
        return new SharedRun(scriptPath, startedPath);
    }

    static void CleanupOldRuns(string root)
    {
        if (!Directory.Exists(root))
        {
            return;
        }

        var cutoff = DateTime.UtcNow.AddDays(-1);
        foreach (var entry in Directory.EnumerateDirectories(root))
        {
            try
            {
                if (Directory.GetLastWriteTimeUtc(entry) < cutoff)
                {
                    Directory.Delete(entry, recursive: true);
                }
            }
            catch
            {
                // A run directory can stay behind if a terminal still has it open.
            }
        }
    }

    static string ScriptLauncherCommand(string scriptPath)
    {
        var bash = FindBash();
        if (bash != null)
        {
            return Quote(bash) + " " + Quote(scriptPath);
        }

        return "powershell.exe -NoExit -File " + Quote(scriptPath);
    }

    static bool WaitForStart(string startedPath)
    {
        var deadline = DateTime.UtcNow.AddSeconds(15);
        while (DateTime.UtcNow < deadline)
        {
            if (File.Exists(startedPath))
            {
                return true;
            }

            Thread.Sleep(50);
        }

        return File.Exists(startedPath);
    }

    static void Start(string fileName, string arguments)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = true,
        });
    }

    static string JoinArguments(IEnumerable<string> arguments) => string.Join(" ", arguments.Select(Quote));

    static string Quote(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }

        if (value.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
        {
            return value;
        }

        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    static string PowerShellQuote(string value) => "'" + value.Replace("'", "''") + "'";

    static string ShellSingleQuote(string value) => "'" + value.Replace("'", "'\\''") + "'";

    static string TomlDoubleQuoted(string value) =>
        "\"" + value
            .Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("\n", "\\n")
            .Replace("\r", "\\r")
            .Replace("\t", "\\t") + "\"";
}
