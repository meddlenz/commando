using System.Windows;
using System.Windows.Controls;
using Commando.Licensing;

namespace Commando.UI;

public sealed class RegistrationWindow : Window
{
    static RegistrationWindow? _instance;

    public static void Present()
    {
        _instance?.Close();
        _instance = new RegistrationWindow();
        _instance.Show();
        _instance.Activate();
    }

    RegistrationWindow()
    {
        Title = "Register Commando";
        Width = 460;
        SizeToContent = SizeToContent.Height;
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
        Content = BuildForm();
    }

    UIElement BuildForm()
    {
        var root = new StackPanel { Margin = new Thickness(24) };
        var purchase = new Button
        {
            Content = "Purchase Commando",
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(10, 4, 10, 4),
        };
        purchase.Click += (_, _) => Browser.Open(AppInfo.PurchaseUrl);
        root.Children.Add(purchase);
        root.Children.Add(new TextBlock
        {
            Text = "Enter the name and email used when your license was issued. Registration keys begin with COMMANDO1. All details are case-sensitive.",
            Foreground = UiKit.Secondary(),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 12, 0, 8),
        });

        var name = Field("Full name");
        var email = Field("Email");
        var key = Field("License key");
        root.Children.Add(name.Panel);
        root.Children.Add(email.Panel);
        root.Children.Add(key.Panel);

        var error = new TextBlock
        {
            Foreground = System.Windows.Media.Brushes.Firebrick,
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 8, 0, 0),
            Visibility = Visibility.Collapsed,
        };
        root.Children.Add(error);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var cancel = new Button { Content = "Cancel", MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(8, 4, 8, 4) };
        cancel.Click += (_, _) => Close();
        var register = new Button { Content = "Register", MinWidth = 80, IsDefault = true, Padding = new Thickness(8, 4, 8, 4) };
        register.Click += (_, _) =>
        {
            try
            {
                LicenseStatus.Register(name.Box.Text, email.Box.Text, key.Box.Text);
                Content = BuildThanks();
            }
            catch (Exception ex)
            {
                error.Text = ex.Message;
                error.Visibility = Visibility.Visible;
            }
        };
        buttons.Children.Add(cancel);
        buttons.Children.Add(register);
        root.Children.Add(buttons);
        return root;
    }

    UIElement BuildThanks()
    {
        var stack = new StackPanel { Margin = new Thickness(24) };
        stack.Children.Add(new TextBlock
        {
            Text = "Thank you for purchasing Commando!",
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        var close = new Button
        {
            Content = "Close",
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 16, 0, 0),
            MinWidth = 80,
            Padding = new Thickness(8, 4, 8, 4),
            IsDefault = true,
        };
        close.Click += (_, _) => Close();
        stack.Children.Add(close);
        return stack;
    }

    static (StackPanel Panel, TextBox Box) Field(string title)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 12, Foreground = UiKit.Secondary() });
        var box = new TextBox { Margin = new Thickness(0, 4, 0, 0), Padding = new Thickness(4, 3, 4, 3) };
        panel.Children.Add(box);
        return (panel, box);
    }
}
