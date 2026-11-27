using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Commando.Preferences;

namespace Commando.UI;

static class UiKit
{
    public static readonly FontFamily IconFont = new("Segoe MDL2 Assets");

    public static TextBlock Icon(string glyph, double size = 16)
    {
        return new TextBlock
        {
            Text = glyph,
            FontFamily = IconFont,
            FontSize = size,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = Accent(),
        };
    }

    public static SolidColorBrush Accent() => Freeze(SystemColors.HighlightColor);

    public static SolidColorBrush Secondary() => Freeze(SystemColors.GrayTextColor);

    public static SolidColorBrush Sidebar() => Freeze(SystemColors.ControlColor);

    public static SolidColorBrush WindowBackground() => Freeze(SystemColors.WindowColor);

    public static SolidColorBrush Banner() => Freeze(Color.FromRgb(0xD6, 0x45, 0x45));

    public static void AttachCommands(Window window)
    {
        window.InputBindings.Add(new KeyBinding(new RelayCommand(SettingsWindow.Present), new KeyGesture(Key.OemComma, ModifierKeys.Control)));
        window.InputBindings.Add(new KeyBinding(new RelayCommand(() => System.Windows.Application.Current.Shutdown()), new KeyGesture(Key.Q, ModifierKeys.Control)));
    }

    public static void ApplyIcon(Window window)
    {
        var image = IconResources.AppIcon();
        if (image != null)
        {
            window.Icon = image;
        }
    }

    public static void Track(Window window) => WindowTracker.Attach(window);

    static SolidColorBrush Freeze(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

sealed class RelayCommand : ICommand
{
    readonly Action _action;

    public RelayCommand(Action action) => _action = action;

    public event EventHandler? CanExecuteChanged
    {
        add { }
        remove { }
    }

    public bool CanExecute(object? parameter) => true;

    public void Execute(object? parameter) => _action();
}

static class WindowTracker
{
    static readonly HashSet<Window> Open = new();

    public static event Action? Changed;

    public static bool HasContentWindows => Open.Count > 0;

    public static void Attach(Window window)
    {
        window.Loaded += (_, _) =>
        {
            Open.Add(window);
            Changed?.Invoke();
        };
        window.Closed += (_, _) =>
        {
            Open.Remove(window);
            Changed?.Invoke();
        };
    }
}

static class Browser
{
    public static void Open(Uri url)
    {
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
    }
}

sealed class ChoiceDialog : Window
{
    public string? Choice { get; private set; }

    ChoiceDialog(string title, string message, IReadOnlyList<string> buttons)
    {
        Title = title;
        Width = 460;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.NoResize;
        Background = UiKit.WindowBackground();
        UiKit.ApplyIcon(this);

        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 16),
        });

        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        for (var index = 0; index < buttons.Count; index++)
        {
            var label = buttons[index];
            var button = new Button
            {
                Content = label,
                MinWidth = 88,
                Margin = new Thickness(8, 0, 0, 0),
                Padding = new Thickness(12, 4, 12, 4),
                IsDefault = index == 0,
                IsCancel = buttons.Count > 1 && index == buttons.Count - 1,
            };
            button.Click += (_, _) =>
            {
                Choice = label;
                DialogResult = true;
            };
            row.Children.Add(button);
        }

        panel.Children.Add(row);
        Content = panel;
    }

    public static string? Show(Window? owner, string title, string message, params string[] buttons)
    {
        var dialog = new ChoiceDialog(title, message, buttons);
        if (owner != null && owner.IsVisible)
        {
            dialog.Owner = owner;
            dialog.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        }

        dialog.ShowDialog();
        return dialog.Choice;
    }
}
