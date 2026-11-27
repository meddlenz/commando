using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Commando.UI;

public sealed class UpdateWindow : Window
{
    static UpdateWindow? _instance;

    readonly bool _required;
    bool _allowClose;

    public static void Present(string version, string message, Uri? updateUrl, bool required, Action onLater)
    {
        if (required && _instance is { _required: true })
        {
            _instance.Activate();
            return;
        }

        if (_instance != null && !_instance._required)
        {
            _instance._allowClose = true;
            _instance.Close();
        }

        _instance = new UpdateWindow(version, message, updateUrl, required, onLater);
        _instance.Show();
        _instance.Activate();
    }

    UpdateWindow(string version, string message, Uri? updateUrl, bool required, Action onLater)
    {
        _required = required;
        Title = required ? "Update Required" : "Update Available";
        Width = 480;
        SizeToContent = SizeToContent.Height;
        MaxHeight = 560;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = UiKit.WindowBackground();
        UiKit.ApplyIcon(this);
        UiKit.AttachCommands(this);
        UiKit.Track(this);

        var root = new StackPanel { Margin = new Thickness(24) };
        var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 16) };
        var icon = new Image { Width = 48, Height = 48, Margin = new Thickness(0, 0, 16, 0) };
        icon.Source = IconResources.AppIcon();
        var titles = new StackPanel();
        titles.Children.Add(new TextBlock { Text = "Commando Update", FontSize = 15, FontWeight = FontWeights.SemiBold });
        titles.Children.Add(new TextBlock { Text = "Version " + version, Margin = new Thickness(0, 4, 0, 0) });
        titles.Children.Add(new TextBlock
        {
            Text = "You're currently on version " + AppInfo.ShortVersion,
            FontSize = 12,
            Foreground = UiKit.Secondary(),
        });
        if (icon.Source != null)
        {
            header.Children.Add(icon);
        }

        header.Children.Add(titles);
        root.Children.Add(header);

        var notes = new Border
        {
            Background = UiKit.Sidebar(),
            BorderBrush = new SolidColorBrush(SystemColors.ControlDarkColor),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12),
            Margin = new Thickness(0, 0, 0, 12),
        };
        var notesStack = new StackPanel();
        notesStack.Children.Add(new TextBlock { Text = "Release Notes", Foreground = UiKit.Secondary(), Margin = new Thickness(0, 0, 0, 8) });
        var scroll = new ScrollViewer { MaxHeight = 140, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        scroll.Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap };
        notesStack.Children.Add(scroll);
        notes.Child = notesStack;
        root.Children.Add(notes);

        var news = new Button
        {
            Content = "View full change log",
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Left,
            Foreground = UiKit.Accent(),
            Cursor = System.Windows.Input.Cursors.Hand,
            Margin = new Thickness(0, 0, 0, 16),
        };
        news.Click += (_, _) => Browser.Open(AppInfo.NewsUrl);
        root.Children.Add(news);
        root.Children.Add(new Separator());

        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        if (!required)
        {
            var later = new Button { Content = "Later", MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(8, 4, 8, 4) };
            later.Click += (_, _) =>
            {
                onLater();
                _allowClose = true;
                Close();
            };
            footer.Children.Add(later);
        }

        var download = new Button
        {
            Content = Updates.UpdateChecker.UpdateActionTitle(),
            MinWidth = 90,
            Padding = new Thickness(8, 4, 8, 4),
            IsDefault = true,
            IsEnabled = updateUrl != null,
        };
        download.Click += (_, _) =>
        {
            if (updateUrl != null && Updates.UpdateChecker.IsAllowedUpdateUrl(updateUrl))
            {
                Browser.Open(updateUrl);
            }

            _allowClose = true;
            Close();
        };
        footer.Children.Add(download);
        root.Children.Add(footer);
        Content = root;
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (_required && !_allowClose)
        {
            e.Cancel = true;
            return;
        }

        if (_instance == this)
        {
            _instance = null;
        }

        base.OnClosing(e);
    }
}
