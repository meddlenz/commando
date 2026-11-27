using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Commando.Execution;
using Commando.Licensing;
using Commando.Models;
using Commando.Ssh;
using Commando.Storage;

namespace Commando.UI;

public sealed class CommandSetsWindow : Window
{
    static CommandSetsWindow? _instance;

    readonly ListBox _list = new();
    readonly TextBlock _emptyList = new();
    readonly Border _banner = new();
    readonly TextBlock _bannerText = new();
    readonly StackPanel _empty = new();
    readonly ScrollViewer _editorScroll = new();
    readonly StackPanel _editor = new();
    readonly DockPanel _toolbar = new();
    readonly Button _deleteButton = new();
    readonly TextBox _nameBox = new();
    readonly CheckBox _sshCheck = new();
    readonly TextBox _serverBox = new();
    readonly StackPanel _serverBlock = new();
    readonly StackPanel _sshActions = new();
    readonly TextBlock _keyFound = new();
    readonly StackPanel _sessionsHost = new();

    readonly List<EditableSession> _sessions = new();
    Guid? _editingId;
    string? _validation;
    bool _suppressSelection;

    public static void Present()
    {
        if (_instance != null && _instance.IsVisible)
        {
            if (_instance.WindowState == WindowState.Minimized)
            {
                _instance.WindowState = WindowState.Normal;
            }

            _instance.Activate();
            return;
        }

        _instance?.Close();
        _instance = new CommandSetsWindow();
        _instance.Show();
        _instance.Activate();
    }

    CommandSetsWindow()
    {
        Title = "Commando";
        Width = 820;
        Height = 580;
        MinWidth = 720;
        MinHeight = 480;
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

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(BuildSidebar());
        var splitter = new Border { Background = new SolidColorBrush(SystemColors.ControlDarkColor) };
        Grid.SetColumn(splitter, 1);
        root.Children.Add(splitter);
        var detail = BuildDetail();
        Grid.SetColumn(detail, 2);
        root.Children.Add(detail);
        Content = root;

        BuildEditorChrome();
        ReloadList();
        ShowEmpty();
        AppEvents.CommandSetsChanged += OnCommandSetsChanged;
        AppEvents.LicenseChanged += OnLicenseChanged;
        Closed += (_, _) =>
        {
            AppEvents.CommandSetsChanged -= OnCommandSetsChanged;
            AppEvents.LicenseChanged -= OnLicenseChanged;
        };
        Activated += (_, _) => UpdateSshOptions();
    }

    UIElement BuildSidebar()
    {
        var panel = new DockPanel { Background = UiKit.Sidebar() };
        var header = new TextBlock
        {
            Text = "Command Sets",
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(16, 12, 16, 12),
            FontSize = 14,
        };
        DockPanel.SetDock(header, Dock.Top);
        panel.Children.Add(header);

        var add = new Button
        {
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 8, 8, 8),
            Margin = new Thickness(8, 0, 8, 0),
            Cursor = Cursors.Hand,
        };
        var addRow = new StackPanel { Orientation = Orientation.Horizontal };
        addRow.Children.Add(UiKit.Icon("\uE710"));
        addRow.Children.Add(new TextBlock { Text = "Add New", Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        add.Content = addRow;
        add.Click += (_, _) => StartCreating();
        DockPanel.SetDock(add, Dock.Top);
        panel.Children.Add(add);

        var settings = new Button
        {
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 10, 8, 10),
            Margin = new Thickness(8, 4, 8, 8),
            Cursor = Cursors.Hand,
        };
        var settingsRow = new StackPanel { Orientation = Orientation.Horizontal };
        var gear = UiKit.Icon("\uE713");
        gear.Foreground = UiKit.Secondary();
        settingsRow.Children.Add(gear);
        settingsRow.Children.Add(new TextBlock { Text = "Settings", Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        settings.Content = settingsRow;
        settings.Click += (_, _) => SettingsWindow.Present();
        DockPanel.SetDock(settings, Dock.Bottom);
        panel.Children.Add(settings);

        _emptyList.Text = "No command sets yet";
        _emptyList.Foreground = UiKit.Secondary();
        _emptyList.Margin = new Thickness(16, 8, 16, 8);
        DockPanel.SetDock(_emptyList, Dock.Top);
        panel.Children.Add(_emptyList);

        _list.BorderThickness = new Thickness(0);
        _list.Background = Brushes.Transparent;
        _list.SelectionChanged += (_, _) =>
        {
            if (_suppressSelection)
            {
                return;
            }

            if (_list.SelectedItem is ListBoxItem item && item.Tag is Guid id)
            {
                var commandSet = CommandStore.CommandSets.FirstOrDefault(set => set.Id == id);
                if (commandSet != null)
                {
                    Edit(commandSet);
                }
            }
        };
        _list.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Delete && _list.SelectedItem is ListBoxItem item && item.Tag is Guid id)
            {
                Delete(id);
            }
        };
        panel.Children.Add(_list);
        return panel;
    }

    UIElement BuildDetail()
    {
        var panel = new DockPanel();
        _banner.Background = UiKit.Banner();
        _banner.Visibility = Visibility.Collapsed;
        _bannerText.Foreground = Brushes.White;
        _bannerText.TextWrapping = TextWrapping.Wrap;
        _bannerText.Margin = new Thickness(16, 10, 16, 10);
        _banner.Child = _bannerText;
        DockPanel.SetDock(_banner, Dock.Top);
        panel.Children.Add(_banner);

        DockPanel.SetDock(_toolbar, Dock.Bottom);
        _toolbar.Visibility = Visibility.Collapsed;
        _toolbar.Background = UiKit.Sidebar();
        _toolbar.Margin = new Thickness(0);
        panel.Children.Add(_toolbar);

        _editorScroll.Visibility = Visibility.Collapsed;
        _editorScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        _editorScroll.Content = _editor;
        panel.Children.Add(_editorScroll);

        _empty.VerticalAlignment = VerticalAlignment.Center;
        _empty.HorizontalAlignment = HorizontalAlignment.Center;
        var prompt = new TextBlock
        {
            Text = ">_",
            FontSize = 40,
            FontFamily = new FontFamily("Consolas"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Opacity = 0.55,
        };
        _empty.Children.Add(prompt);
        _empty.Children.Add(new TextBlock
        {
            Text = "Select a command set",
            FontSize = 20,
            FontWeight = FontWeights.Medium,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 12, 0, 0),
        });
        _empty.Children.Add(new TextBlock
        {
            Text = "Choose one from the list, or create a new command set.",
            Foreground = UiKit.Secondary(),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Width = 320,
            Margin = new Thickness(0, 8, 0, 0),
        });
        var create = new Button { Content = "Create Command Set", HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 0), Padding = new Thickness(12, 4, 12, 4) };
        create.Click += (_, _) => StartCreating();
        _empty.Children.Add(create);
        panel.Children.Add(_empty);
        return panel;
    }

    void BuildEditorChrome()
    {
        _editor.Margin = new Thickness(24);
        _editor.Children.Add(Section("Name", "Shown in the notification area when you run this set.", _nameBox));
        _nameBox.Margin = new Thickness(0, 4, 0, 0);
        _nameBox.Padding = new Thickness(4, 3, 4, 3);

        var ssh = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
        ssh.Children.Add(new TextBlock { Text = "SSH", FontWeight = FontWeights.SemiBold });
        _sshCheck.Content = "Connect to a remote server";
        _sshCheck.Margin = new Thickness(0, 8, 0, 0);
        _sshCheck.Checked += (_, _) => UpdateSshOptions();
        _sshCheck.Unchecked += (_, _) => UpdateSshOptions();
        ssh.Children.Add(_sshCheck);
        _serverBlock.Margin = new Thickness(0, 8, 0, 0);
        _serverBlock.Children.Add(new TextBlock
        {
            Text = "Use user@host or user@host:port, not the full ssh command.",
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            TextWrapping = TextWrapping.Wrap,
        });
        _serverBox.FontFamily = new FontFamily("Consolas");
        _serverBox.Margin = new Thickness(0, 6, 0, 0);
        _serverBox.Padding = new Thickness(4, 3, 4, 3);
        _serverBox.TextChanged += (_, _) => UpdateSshOptions();
        _serverBlock.Children.Add(_serverBox);
        _sshActions.Margin = new Thickness(0, 8, 0, 0);
        var keyButton = new Button { Content = "Set Up SSH Key...", HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(10, 3, 10, 3) };
        keyButton.Click += (_, _) => SetUpSshKey();
        var keyRow = new StackPanel { Orientation = Orientation.Horizontal };
        keyRow.Children.Add(keyButton);
        _keyFound.Text = "Local key found";
        _keyFound.Foreground = new SolidColorBrush(Color.FromRgb(0x1B, 0x7F, 0x3A));
        _keyFound.Margin = new Thickness(10, 0, 0, 0);
        _keyFound.VerticalAlignment = VerticalAlignment.Center;
        keyRow.Children.Add(_keyFound);
        _sshActions.Children.Add(keyRow);
        _sshActions.Children.Add(new TextBlock
        {
            Text = "Set up an SSH key once to connect without entering a password.",
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            Margin = new Thickness(0, 6, 0, 0),
            TextWrapping = TextWrapping.Wrap,
        });
        _serverBlock.Children.Add(_sshActions);
        ssh.Children.Add(_serverBlock);
        _editor.Children.Add(ssh);

        var commands = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
        commands.Children.Add(new TextBlock { Text = "Commands", FontWeight = FontWeights.SemiBold });
        commands.Children.Add(new TextBlock
        {
            Text = "Steps in a session run in order. Parallel sessions split the terminal window or open additional windows if splitting isn't available.",
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 2, 0, 8),
        });
        commands.Children.Add(_sessionsHost);
        _editor.Children.Add(commands);

        _deleteButton.Content = "Delete Command Set";
        _deleteButton.Foreground = Brushes.Firebrick;
        _deleteButton.Click += (_, _) =>
        {
            if (_editingId != null)
            {
                Delete(_editingId.Value);
            }
        };
        DockPanel.SetDock(_deleteButton, Dock.Left);
        _toolbar.Children.Add(_deleteButton);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(20, 12, 20, 12) };
        var cancel = new Button { Content = "Cancel", MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(8, 4, 8, 4) };
        cancel.Click += (_, _) => CancelEditing();
        var save = new Button { Content = "Save", MinWidth = 80, IsDefault = true, Padding = new Thickness(8, 4, 8, 4) };
        save.Click += (_, _) => Save();
        actions.Children.Add(cancel);
        actions.Children.Add(save);
        DockPanel.SetDock(actions, Dock.Right);
        _toolbar.Children.Add(actions);
    }

    static StackPanel Section(string title, string help, UIElement content)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new TextBlock
        {
            Text = help,
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            Margin = new Thickness(0, 2, 0, 4),
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(content);
        return panel;
    }

    void OnCommandSetsChanged()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(OnCommandSetsChanged);
            return;
        }

        ReloadList();
    }

    void OnLicenseChanged()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(OnLicenseChanged);
            return;
        }

        ReloadList();
        UpdateBanner();
    }

    void ReloadList()
    {
        var sets = CommandStore.CommandSets;
        _suppressSelection = true;
        _list.Items.Clear();
        foreach (var commandSet in sets)
        {
            _list.Items.Add(CreateRow(commandSet));
        }

        _emptyList.Visibility = sets.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (_editingId != null)
        {
            foreach (ListBoxItem item in _list.Items)
            {
                if (item.Tag is Guid id && id == _editingId)
                {
                    _list.SelectedItem = item;
                    break;
                }
            }

            if (sets.All(set => set.Id != _editingId))
            {
                CancelEditing();
            }
        }

        _suppressSelection = false;
        UpdateBanner();
    }

    ListBoxItem CreateRow(CommandSet commandSet)
    {
        var item = new ListBoxItem { Tag = commandSet.Id, Padding = new Thickness(4, 2, 4, 2), HorizontalContentAlignment = HorizontalAlignment.Stretch };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var icon = UiKit.Icon(commandSet.IsRemote ? "\uE8B7" : "\uE756");
        Grid.SetColumn(icon, 0);
        var text = new StackPanel { Margin = new Thickness(8, 6, 8, 6) };
        text.Children.Add(new TextBlock
        {
            Text = string.IsNullOrEmpty(commandSet.Name) ? "Untitled" : commandSet.Name,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        text.Children.Add(new TextBlock
        {
            Text = commandSet.MenuSubtitle,
            FontSize = 12,
            Foreground = UiKit.Secondary(),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        Grid.SetColumn(text, 1);
        var play = new Button
        {
            Content = UiKit.Icon("\uE768"),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(6),
            Cursor = Cursors.Hand,
            ToolTip = "Run",
        };
        var id = commandSet.Id;
        play.PreviewMouseLeftButtonDown += (_, e) =>
        {
            e.Handled = true;
            Run(id);
        };
        Grid.SetColumn(play, 2);
        grid.Children.Add(icon);
        grid.Children.Add(text);
        grid.Children.Add(play);
        item.Content = grid;
        return item;
    }

    void ShowEmpty()
    {
        _empty.Visibility = Visibility.Visible;
        _editorScroll.Visibility = Visibility.Collapsed;
        _toolbar.Visibility = Visibility.Collapsed;
        UpdateBanner();
    }

    void ShowEditor()
    {
        _empty.Visibility = Visibility.Collapsed;
        _editorScroll.Visibility = Visibility.Visible;
        _toolbar.Visibility = Visibility.Visible;
        _deleteButton.Visibility = _editingId == null ? Visibility.Collapsed : Visibility.Visible;
        UpdateSshOptions();
        RebuildSessions();
        UpdateBanner();
    }

    void StartCreating()
    {
        try
        {
            LicenseStatus.EnsureCanAddCommandSet(CommandStore.CommandSets.Count);
        }
        catch (Exception ex)
        {
            _validation = ex.Message;
            UpdateBanner();
            return;
        }

        _editingId = null;
        _nameBox.Text = "";
        _serverBox.Text = "";
        _sshCheck.IsChecked = false;
        _sessions.Clear();
        _sessions.Add(new EditableSession());
        _validation = null;
        _suppressSelection = true;
        _list.SelectedItem = null;
        _suppressSelection = false;
        ShowEditor();
    }

    void Edit(CommandSet commandSet)
    {
        _editingId = commandSet.Id;
        _nameBox.Text = commandSet.Name;
        _serverBox.Text = commandSet.ServerDetails;
        _sshCheck.IsChecked = commandSet.IsRemote;
        _sessions.Clear();
        foreach (var session in commandSet.Sessions)
        {
            var editable = new EditableSession { Name = session.Name };
            editable.Steps.Clear();
            foreach (var step in session.Steps)
            {
                editable.Steps.Add(new EditableStep { Text = step });
            }

            if (editable.Steps.Count == 0)
            {
                editable.Steps.Add(new EditableStep());
            }

            _sessions.Add(editable);
        }

        if (_sessions.Count == 0)
        {
            _sessions.Add(new EditableSession());
        }

        _validation = null;
        ShowEditor();
    }

    void Save()
    {
        var name = _nameBox.Text.Trim();
        if (name.Length == 0)
        {
            _validation = "Name is required.";
            UpdateBanner();
            return;
        }

        var server = _sshCheck.IsChecked == true ? SshConnection.Normalise(_serverBox.Text) : "";
        if (server.Length > 0 && SshConnection.Parse(server) == null)
        {
            _validation = "Server must be username@host or username@host:port (without ssh).";
            UpdateBanner();
            return;
        }

        var mapped = _sessions.Select(session => new CommandSession(session.Name, session.Steps.Select(step => step.Text).ToList())).ToList();
        var pruned = mapped.Where(session => session.Steps.Any(step => step.Trim().Length > 0)).ToList();
        var sessions = pruned.Count == 0
            ? new List<CommandSession> { new(mapped.Count > 0 ? mapped[0].Name : "") }
            : pruned;
        var hasCommand = sessions.Any(session => session.Steps.Any(step => step.Trim().Length > 0));
        if (!hasCommand && server.Length == 0)
        {
            _validation = "Add at least one command step.";
            UpdateBanner();
            return;
        }

        try
        {
            LicenseStatus.EnsureCanSaveSessions(sessions.Count);
            if (_editingId == null)
            {
                LicenseStatus.EnsureCanAddCommandSet(CommandStore.CommandSets.Count);
            }
        }
        catch (Exception ex)
        {
            _validation = ex.Message;
            UpdateBanner();
            return;
        }

        var id = _editingId ?? Guid.NewGuid();
        var updated = new CommandSet(name, server, sessions: sessions, id: id);
        var sets = CommandStore.CommandSets;
        var index = sets.FindIndex(set => set.Id == id);
        if (index >= 0)
        {
            sets[index] = updated;
        }
        else
        {
            sets.Add(updated);
        }

        CommandStore.CommandSets = sets;
        CancelEditing();
    }

    void CancelEditing()
    {
        _editingId = null;
        _validation = null;
        _suppressSelection = true;
        _list.SelectedItem = null;
        _suppressSelection = false;
        ShowEmpty();
    }

    void Delete(Guid id)
    {
        var sets = CommandStore.CommandSets;
        ExampleCommandSet.MarkRemovedIfNeeded(id);
        CredentialStore.DeletePassword(id);
        sets.RemoveAll(set => set.Id == id);
        CommandStore.CommandSets = sets;
        if (_editingId == id)
        {
            CancelEditing();
        }
    }

    void Run(Guid id)
    {
        var commandSet = CommandStore.CommandSets.FirstOrDefault(set => set.Id == id);
        if (commandSet == null)
        {
            ReloadList();
            return;
        }

        try
        {
            CommandExecutor.Run(commandSet);
            _validation = null;
        }
        catch (Exception ex)
        {
            _validation = ex.Message;
        }

        UpdateBanner();
    }

    void SetUpSshKey()
    {
        var connection = SshConnection.Parse(SshConnection.Normalise(_serverBox.Text));
        if (connection == null)
        {
            _validation = "Enter a valid server (username@host) before setting up an SSH key.";
            UpdateBanner();
            return;
        }

        var terminal = Commando.Preferences.TerminalAppSettings.SelectedAppName;
        var message =
            "Commando will open " + terminal + " and install an SSH key on " + connection.Username + "@" + connection.Host + ".\n\n"
            + "Enter the server password in the terminal when prompted, and verify the server fingerprint before continuing. SSH authenticates there, Commando does not receive or store that password.";
        if (ChoiceDialog.Show(this, "Set Up SSH Key", message, "Open Terminal", "Cancel") != "Open Terminal")
        {
            return;
        }

        _validation = null;
        UpdateBanner();
        try
        {
            SshKeySetup.Install(connection);
        }
        catch (Exception ex)
        {
            ChoiceDialog.Show(this, "SSH Key Setup Failed", ex.Message, "OK");
        }
    }

    void UpdateSshOptions()
    {
        var enabled = _sshCheck.IsChecked == true;
        _serverBlock.Visibility = enabled ? Visibility.Visible : Visibility.Collapsed;
        var parsed = enabled ? SshConnection.Parse(SshConnection.Normalise(_serverBox.Text)) : null;
        _sshActions.Visibility = parsed != null ? Visibility.Visible : Visibility.Collapsed;
        _keyFound.Visibility = parsed != null && SshKeySetup.HasLocalKey() ? Visibility.Visible : Visibility.Collapsed;
    }

    void RebuildSessions()
    {
        _sessionsHost.Children.Clear();
        for (var index = 0; index < _sessions.Count; index++)
        {
            var session = _sessions[index];
            if (index > 0)
            {
                _sessionsHost.Children.Add(new Separator { Margin = new Thickness(0, 8, 0, 8) });
            }

            if (_sessions.Count > 1)
            {
                var header = new Grid { Margin = new Thickness(0, 0, 0, 8) };
                header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var label = new TextBlock { Text = "Session " + (index + 1), Foreground = UiKit.Secondary(), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
                var name = new TextBox { Text = session.Name, Padding = new Thickness(4, 3, 4, 3) };
                name.TextChanged += (_, _) => session.Name = name.Text;
                var remove = new Button { Content = "Remove", Foreground = Brushes.Firebrick, Margin = new Thickness(8, 0, 0, 0), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = Cursors.Hand };
                var sessionId = session.Id;
                remove.Click += (_, _) =>
                {
                    if (_sessions.Count <= 1)
                    {
                        return;
                    }

                    _sessions.RemoveAll(item => item.Id == sessionId);
                    RebuildSessions();
                };
                Grid.SetColumn(name, 1);
                Grid.SetColumn(remove, 2);
                header.Children.Add(label);
                header.Children.Add(name);
                header.Children.Add(remove);
                _sessionsHost.Children.Add(header);
            }

            for (var stepIndex = 0; stepIndex < session.Steps.Count; stepIndex++)
            {
                _sessionsHost.Children.Add(BuildStepRow(session, session.Steps[stepIndex], stepIndex + 1));
            }

            var addStep = LinkButton("\uE710", "Add Step");
            var addTarget = session.Id;
            addStep.Click += (_, _) =>
            {
                var target = _sessions.FirstOrDefault(item => item.Id == addTarget);
                target?.Steps.Add(new EditableStep());
                RebuildSessions();
            };
            addStep.Margin = new Thickness(0, 8, 0, 0);
            addStep.HorizontalAlignment = HorizontalAlignment.Center;
            _sessionsHost.Children.Add(addStep);
        }

        _sessionsHost.Children.Add(new Separator { Margin = new Thickness(0, 12, 0, 8) });
        var addSession = LinkButton("\uE8C6", "Add Parallel Session");
        addSession.HorizontalAlignment = HorizontalAlignment.Center;
        addSession.Click += (_, _) =>
        {
            try
            {
                LicenseStatus.EnsureCanAddSession();
            }
            catch (Exception ex)
            {
                _validation = ex.Message;
                UpdateBanner();
                return;
            }

            _sessions.Add(new EditableSession());
            _validation = null;
            RebuildSessions();
            UpdateBanner();
        };
        _sessionsHost.Children.Add(addSession);
    }

    UIElement BuildStepRow(EditableSession session, EditableStep step, int number)
    {
        var grid = new Grid { Margin = new Thickness(0, 4, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new TextBlock
        {
            Text = number.ToString(),
            FontFamily = new FontFamily("Consolas"),
            Foreground = UiKit.Secondary(),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 0, 8, 0),
        });
        var box = new TextBox
        {
            Text = step.Text,
            FontFamily = new FontFamily("Consolas"),
            Padding = new Thickness(4, 3, 4, 3),
        };
        var delete = new Button
        {
            Content = UiKit.Icon("\uE738"),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = Brushes.Firebrick,
            Margin = new Thickness(6, 0, 0, 0),
            Cursor = Cursors.Hand,
            Visibility = string.IsNullOrEmpty(step.Text) ? Visibility.Collapsed : Visibility.Visible,
        };
        var stepId = step.Id;
        box.TextChanged += (_, _) =>
        {
            step.Text = box.Text;
            delete.Visibility = string.IsNullOrEmpty(box.Text) ? Visibility.Collapsed : Visibility.Visible;
        };
        delete.Click += (_, _) =>
        {
            session.Steps.RemoveAll(item => item.Id == stepId);
            if (session.Steps.Count == 0)
            {
                session.Steps.Add(new EditableStep());
            }

            RebuildSessions();
        };
        Grid.SetColumn(box, 1);
        Grid.SetColumn(delete, 2);
        grid.Children.Add(box);
        grid.Children.Add(delete);
        return grid;
    }

    static Button LinkButton(string glyph, string title)
    {
        var button = new Button
        {
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Cursor = Cursors.Hand,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(UiKit.Icon(glyph));
        row.Children.Add(new TextBlock { Text = title, Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Foreground = UiKit.Accent() });
        button.Content = row;
        return button;
    }

    void UpdateBanner()
    {
        string? message = null;
        if (LicenseStatus.IsRevoked)
        {
            message = RegistrationException.MessageFor(RegistrationErrorKind.Revoked);
        }
        else if (!string.IsNullOrEmpty(_validation))
        {
            message = _validation;
        }

        if (message == null)
        {
            _banner.Visibility = Visibility.Collapsed;
            return;
        }

        _bannerText.Text = message;
        _banner.Visibility = Visibility.Visible;
    }

    sealed class EditableStep
    {
        public Guid Id { get; } = Guid.NewGuid();
        public string Text { get; set; } = "";
    }

    sealed class EditableSession
    {
        public Guid Id { get; } = Guid.NewGuid();
        public string Name { get; set; } = "";
        public List<EditableStep> Steps { get; } = new() { new EditableStep() };
    }
}
