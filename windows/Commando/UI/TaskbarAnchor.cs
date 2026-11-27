using System.Windows;
using Commando.Preferences;

namespace Commando.UI;

sealed class TaskbarAnchor : Window
{
    bool _handling;
    bool _allowClose;

    public TaskbarAnchor()
    {
        Title = "Commando";
        Width = 160;
        Height = 40;
        WindowStyle = WindowStyle.ToolWindow;
        ShowInTaskbar = false;
        ShowActivated = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = -20000;
        Top = -20000;
        Opacity = 0;
        ResizeMode = ResizeMode.NoResize;
        UiKit.ApplyIcon(this);
        WindowTracker.Changed += UpdateVisibility;
        AppEvents.PreferencesChanged += UpdateVisibility;
        Loaded += (_, _) =>
        {
            WindowState = WindowState.Minimized;
            UpdateVisibility();
        };
    }

    public void AllowClose() => _allowClose = true;

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);
        if (_handling || WindowState == WindowState.Minimized)
        {
            return;
        }

        _handling = true;
        try
        {
            WindowState = WindowState.Minimized;
            CommandSetsWindow.Present();
        }
        finally
        {
            _handling = false;
        }
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            WindowState = WindowState.Minimized;
            return;
        }

        WindowTracker.Changed -= UpdateVisibility;
        AppEvents.PreferencesChanged -= UpdateVisibility;
        base.OnClosing(e);
    }

    void UpdateVisibility()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(UpdateVisibility);
            return;
        }

        ShowInTaskbar = !DockIconSettings.IsHidden && !WindowTracker.HasContentWindows;
    }
}
