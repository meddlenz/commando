using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Commando.Licensing;

namespace Commando.UI;

public sealed class AboutWindow : Window
{
    static AboutWindow? _instance;

    readonly StackPanel _licenseHost = new();
    string? _pendingKey;
    DateTime _pendingAt;

    public static void Present()
    {
        if (_instance == null)
        {
            _instance = new AboutWindow();
        }

        _instance.Show();
        _instance.Activate();
        _instance.RefreshLicense();
    }

    AboutWindow()
    {
        Title = "About";
        Width = 380;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = UiKit.WindowBackground();
        UiKit.ApplyIcon(this);
        UiKit.AttachCommands(this);
        UiKit.Track(this);
        Closed += (_, _) =>
        {
            _pendingKey = null;
            if (_instance == this)
            {
                _instance = null;
            }
        };

        var stack = new StackPanel { Margin = new Thickness(32), Width = 316 };
        var icon = new Image { Width = 64, Height = 64, HorizontalAlignment = HorizontalAlignment.Center };
        icon.Source = IconResources.AppIcon();
        if (icon.Source == null)
        {
            stack.Children.Add(new TextBlock { Text = "CR", FontSize = 36, HorizontalAlignment = HorizontalAlignment.Center, Foreground = UiKit.Accent() });
        }
        else
        {
            stack.Children.Add(icon);
        }

        stack.Children.Add(new TextBlock
        {
            Text = AppInfo.Name,
            FontSize = 22,
            FontWeight = FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 16, 0, 0),
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Version " + AppInfo.Version,
            Foreground = UiKit.Secondary(),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0),
        });
        stack.Children.Add(_licenseHost);
        if (!string.IsNullOrEmpty(AppInfo.Copyright))
        {
            stack.Children.Add(new TextBlock
            {
                Text = AppInfo.Copyright,
                FontSize = 12,
                Foreground = UiKit.Secondary(),
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
                Margin = new Thickness(0, 12, 0, 0),
            });
        }

        var company = Link("Manticore Software", () => Browser.Open(AppInfo.CompanyUrl));
        company.HorizontalAlignment = HorizontalAlignment.Center;
        company.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(company);
        var links = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        links.Children.Add(Link("Privacy Policy", () => Browser.Open(AppInfo.PrivacyUrl)));
        links.Children.Add(Link("Terms of Use", () => Browser.Open(AppInfo.TermsUrl)));
        stack.Children.Add(links);
        Content = stack;
        PreviewKeyDown += OnPreviewKeyDown;
        AppEvents.LicenseChanged += RefreshLicense;
        Closed += (_, _) => AppEvents.LicenseChanged -= RefreshLicense;
        RefreshLicense();
    }

    void RefreshLicense()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(RefreshLicense);
            return;
        }

        _licenseHost.Children.Clear();
        _licenseHost.Margin = new Thickness(0, 12, 0, 0);
        if (LicenseStatus.IsRevoked)
        {
            _licenseHost.Children.Add(new TextBlock
            {
                Text = "This license has been revoked. Please get in touch with Manticore SW for more information.",
                FontSize = 12,
                Foreground = UiKit.Secondary(),
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
            });
            var enter = Link("Enter license key", RegistrationWindow.Present);
            enter.HorizontalAlignment = HorizontalAlignment.Center;
            enter.Margin = new Thickness(0, 8, 0, 0);
            _licenseHost.Children.Add(enter);
        }
        else if (LicenseStatus.RegisteredLine is { } line)
        {
            _licenseHost.Children.Add(new TextBlock
            {
                Text = line,
                FontSize = 12,
                Foreground = UiKit.Secondary(),
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
            });
        }
        else
        {
            var enter = Link("Enter license key", RegistrationWindow.Present);
            enter.HorizontalAlignment = HorizontalAlignment.Center;
            _licenseHost.Children.Add(enter);
        }
    }

    void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (!IsActive || (Keyboard.Modifiers & ModifierKeys.Control) == 0)
        {
            _pendingKey = null;
            return;
        }

        var character = e.Key == Key.D ? "d" : e.Key == Key.R ? "r" : null;
        if (character == null)
        {
            _pendingKey = null;
            return;
        }

        if (_pendingKey != null && _pendingKey != character && DateTime.UtcNow - _pendingAt <= TimeSpan.FromSeconds(1.5))
        {
            _pendingKey = null;
            LicenseStatus.Clear();
            RegistrationWindow.Present();
            return;
        }

        _pendingKey = character;
        _pendingAt = DateTime.UtcNow;
    }

    static Button Link(string text, Action action)
    {
        var button = new Button
        {
            Content = text,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = UiKit.Accent(),
            Cursor = System.Windows.Input.Cursors.Hand,
            Padding = new Thickness(6, 2, 6, 2),
        };
        button.Click += (_, _) => action();
        return button;
    }
}
