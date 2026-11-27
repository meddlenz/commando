using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Commando.Models;
using Commando.Preferences;
using Commando.Storage;
using Microsoft.Win32;

namespace Commando.UI;

public sealed class SettingsWindow : Window
{
    static SettingsWindow? _instance;

    public static void Present()
    {
        _instance?.Close();
        _instance = new SettingsWindow();
        _instance.Show();
        _instance.Activate();
    }

    SettingsWindow()
    {
        Title = "Settings";
        Width = 440;
        Height = 520;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = UiKit.WindowBackground();
        UiKit.ApplyIcon(this);
        UiKit.AttachCommands(this);
        UiKit.Track(this);
        Closed += (_, _) =>
        {
            if (_instance == this)
            {
                _instance = null;
            }
        };

        var tabs = new TabControl { Margin = new Thickness(8) };
        tabs.Items.Add(new TabItem { Header = "General", Content = BuildGeneral() });
        tabs.Items.Add(new TabItem { Header = "Command Sets", Content = BuildCommandSets() });
        Content = tabs;
    }

    UIElement BuildGeneral()
    {
        var stack = new StackPanel { Margin = new Thickness(16, 12, 16, 16) };
        var launch = new CheckBox { Content = "Launch at login", IsChecked = LaunchAtLoginSettings.IsEnabled };
        launch.Checked += (_, _) => SetLaunch(launch, true);
        launch.Unchecked += (_, _) => SetLaunch(launch, false);
        stack.Children.Add(launch);

        var hide = new CheckBox { Content = "Hide taskbar button", Margin = new Thickness(0, 10, 0, 0), IsChecked = DockIconSettings.IsHidden };
        hide.Checked += (_, _) => DockIconSettings.SetHidden(true);
        hide.Unchecked += (_, _) => DockIconSettings.SetHidden(false);
        stack.Children.Add(hide);
        stack.Children.Add(Help("Commando runs from the notification area when hidden."));
        stack.Children.Add(new Separator { Margin = new Thickness(0, 12, 0, 12) });
        stack.Children.Add(Help("Terminal choice"));

        var appRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        var icon = new Image { Width = 32, Height = 32, Margin = new Thickness(0, 0, 10, 0) };
        try
        {
            using var associated = System.Drawing.Icon.ExtractAssociatedIcon(TerminalAppSettings.SelectedAppPath);
            if (associated != null)
            {
                icon.Source = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                    associated.Handle,
                    Int32Rect.Empty,
                    System.Windows.Media.Imaging.BitmapSizeOptions.FromWidthAndHeight(32, 32));
            }
        }
        catch
        {
            // The path can be an execution alias without an extractable icon.
        }

        var names = new StackPanel();
        names.Children.Add(new TextBlock { Text = TerminalAppSettings.SelectedAppName, FontWeight = FontWeights.Medium, TextTrimming = TextTrimming.CharacterEllipsis });
        names.Children.Add(new TextBlock
        {
            Text = TerminalAppSettings.SelectedAppPath,
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        appRow.Children.Add(icon);
        appRow.Children.Add(names);
        stack.Children.Add(appRow);

        var choose = new Button { Content = "Choose Terminal App...", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 10, 0, 0), Padding = new Thickness(10, 4, 10, 4) };
        choose.Click += (_, _) => ChooseTerminal();
        stack.Children.Add(choose);
        stack.Children.Add(new Separator { Margin = new Thickness(0, 12, 0, 12) });

        var iconRow = new StackPanel { Orientation = Orientation.Horizontal };
        iconRow.Children.Add(new TextBlock { Text = "Notification icon:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var preview = new Image { Width = 18, Height = 18, Margin = new Thickness(0, 0, 8, 0) };
        var combo = new ComboBox { Width = 180, VerticalAlignment = VerticalAlignment.Center };
        foreach (var option in MenuBarIconSettings.All)
        {
            combo.Items.Add(new ComboBoxItem { Content = MenuBarIconSettings.Title(option), Tag = option });
        }

        void SyncIcon()
        {
            var selected = MenuBarIconSettings.Selected;
            preview.Source = IconResources.Preview(selected);
            foreach (ComboBoxItem item in combo.Items)
            {
                if (item.Tag is MenuBarIconSettings.Option option && option == selected)
                {
                    combo.SelectedItem = item;
                    break;
                }
            }
        }

        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedItem is ComboBoxItem item && item.Tag is MenuBarIconSettings.Option option && option != MenuBarIconSettings.Selected)
            {
                MenuBarIconSettings.Selected = option;
                SyncIcon();
            }
        };
        SyncIcon();
        iconRow.Children.Add(preview);
        iconRow.Children.Add(combo);
        stack.Children.Add(iconRow);
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    UIElement BuildCommandSets()
    {
        var stack = new StackPanel { Margin = new Thickness(16, 12, 16, 16) };
        var cloud = new CheckBox { Content = "Sync via iCloud", IsChecked = CommandStore.IsCloudSyncEnabled };
        cloud.Checked += (_, _) => SetCloud(cloud, true);
        cloud.Unchecked += (_, _) => SetCloud(cloud, false);
        stack.Children.Add(cloud);
        stack.Children.Add(Help("Keeps command sets up to date across devices using this iCloud account."));
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        var import = new Button { Content = "Import", MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(8, 4, 8, 4) };
        import.Click += (_, _) => ImportSets();
        var export = new Button { Content = "Export", MinWidth = 80, Padding = new Thickness(8, 4, 8, 4) };
        export.Click += (_, _) => ExportSets();
        row.Children.Add(import);
        row.Children.Add(export);
        stack.Children.Add(row);
        return stack;
    }

    void SetLaunch(CheckBox box, bool enabled)
    {
        try
        {
            LaunchAtLoginSettings.SetEnabled(enabled);
        }
        catch (Exception ex)
        {
            System.Media.SystemSounds.Beep.Play();
            ChoiceDialog.Show(this, "Unable to update preference", ex.Message, "Ok");
        }

        box.IsChecked = LaunchAtLoginSettings.IsEnabled;
    }

    void SetCloud(CheckBox box, bool enabled)
    {
        try
        {
            CommandStore.SetCloudSyncEnabled(enabled);
        }
        catch (Exception ex)
        {
            System.Media.SystemSounds.Beep.Play();
            ChoiceDialog.Show(this, "Unable to update command sets", ex.Message, "Ok");
        }

        box.IsChecked = CommandStore.IsCloudSyncEnabled;
    }

    void ChooseTerminal()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Choose a Terminal Application",
            Filter = "Applications (*.exe)|*.exe",
            CheckFileExists = true,
        };
        var current = TerminalAppSettings.SelectedAppPath;
        var directory = Path.GetDirectoryName(current);
        if (!string.IsNullOrEmpty(directory) && Directory.Exists(directory))
        {
            dialog.InitialDirectory = directory;
        }

        if (dialog.ShowDialog(this) != true || string.IsNullOrEmpty(dialog.FileName))
        {
            return;
        }

        TerminalAppSettings.SelectedAppPath = dialog.FileName;
        if (!TerminalAppSettings.IsOfficiallySupported(dialog.FileName))
        {
            var selectedName = TerminalAppSettings.DisplayName(dialog.FileName);
            ChoiceDialog.Show(
                this,
                "Terminal app may not be fully supported",
                "Commando officially supports "
                + string.Join(", ", TerminalAppSettings.SupportedTerminalNames)
                + ". Commando will try a generic launch method with "
                + selectedName
                + ", it's unlikely to work.",
                "Continue");
        }

        if (TerminalAppSettings.OfficialName(dialog.FileName) == "Warp"
            && !Directory.Exists(WarpConfigAccess.DefaultConfigDirectory(dialog.FileName)))
        {
            PromptForWarp(dialog.FileName);
        }

        Close();
        Present();
    }

    void PromptForWarp(string appPath)
    {
        var directoryName = WarpConfigAccess.ConfigDirectoryName(appPath);
        var displayPath = "~/" + directoryName;
        var choice = ChoiceDialog.Show(
            this,
            "Allow access to " + displayPath,
            "Warp reads custom tab configurations from " + displayPath + "/tab_configs. Commando needs one-time permission to write its commando.toml file there.\n\nThe next dialog will try to find " + displayPath + " so you can select it. Select the " + directoryName + " folder itself.",
            "Choose " + directoryName + " Folder",
            "Cancel");
        if (choice == null || choice.StartsWith("Cancel", StringComparison.Ordinal))
        {
            return;
        }

        var browser = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Select the " + directoryName + " folder.",
            UseDescriptionForTitle = true,
            InitialDirectory = WarpConfigAccess.DefaultConfigDirectory(appPath),
        };
        while (browser.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            if (WarpConfigAccess.IsExpectedConfigDirectory(browser.SelectedPath, appPath))
            {
                return;
            }

            var retry = ChoiceDialog.Show(
                this,
                "That isn't the " + directoryName + " folder",
                "You selected:\n" + browser.SelectedPath + "\n\nCommando needs:\n" + displayPath,
                "Try Again",
                "Cancel");
            if (retry != "Try Again")
            {
                return;
            }
        }
    }

    void ImportSets()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Import Command Sets",
            Filter = "JSON (*.json)|*.json",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) != true || string.IsNullOrEmpty(dialog.FileName))
        {
            return;
        }

        try
        {
            CommandSetDocument.Decode(File.ReadAllBytes(dialog.FileName));
        }
        catch (Exception ex)
        {
            ChoiceDialog.Show(this, "Unable to update command sets", ex.Message, "Ok");
            return;
        }

        var choice = ChoiceDialog.Show(
            this,
            "Import Command Sets",
            "Do you want to merge these command sets with your existing ones or replace them?",
            "Merge",
            "Replace",
            "Cancel");
        if (choice != "Merge" && choice != "Replace")
        {
            return;
        }

        try
        {
            CommandStore.ImportDocument(dialog.FileName, choice == "Merge" ? CommandStore.ImportMode.Merge : CommandStore.ImportMode.Replace);
        }
        catch (Exception ex)
        {
            ChoiceDialog.Show(this, "Unable to update command sets", ex.Message, "Ok");
        }
    }

    void ExportSets()
    {
        var dialog = new SaveFileDialog
        {
            Title = "Export Command Sets",
            Filter = "JSON (*.json)|*.json",
            FileName = AppStoragePaths.CommandSetsFileName,
            AddExtension = true,
        };
        if (dialog.ShowDialog(this) != true || string.IsNullOrEmpty(dialog.FileName))
        {
            return;
        }

        try
        {
            CommandStore.ExportDocument(dialog.FileName);
        }
        catch (Exception ex)
        {
            ChoiceDialog.Show(this, "Unable to update command sets", ex.Message, "Ok");
        }
    }

    static TextBlock Help(string text) => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = UiKit.Secondary(),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 6, 0, 0),
    };
}
