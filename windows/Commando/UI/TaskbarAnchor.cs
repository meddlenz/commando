using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Commando.Preferences;

namespace Commando.UI;

sealed class TaskbarAnchor : Window
{
    const int GwlExStyle = -20;
    const int WsExToolWindow = 0x00000080;
    const int WsExAppWindow = 0x00040000;
    const int WmSysCommand = 0x0112;
    const int ScRestore = 0xF120;
    const int SwShowMinNoActive = 7;
    const uint SwpNoSize = 0x0001;
    const uint SwpNoMove = 0x0002;
    const uint SwpNoZOrder = 0x0004;
    const uint SwpNoActivate = 0x0010;
    const uint SwpFrameChanged = 0x0020;

    bool _handling;
    bool _allowClose;
    HwndSource? _source;

    public TaskbarAnchor()
    {
        Title = "Commando";
        Width = 160;
        Height = 40;
        WindowStyle = WindowStyle.SingleBorderWindow;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        ShowInTaskbar = !DockIconSettings.IsHidden;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowState = WindowState.Minimized;
        UiKit.ApplyIcon(this);
        SourceInitialized += (_, _) =>
        {
            HookWindow();
            ApplyTaskbarStyle();
        };
        WindowTracker.Changed += UpdateVisibility;
        AppEvents.PreferencesChanged += UpdateVisibility;
    }

    public void AllowClose()
    {
        _allowClose = true;
        _source?.RemoveHook(WndProc);
    }

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);
        if (_handling || WindowState == WindowState.Minimized || !ShowInTaskbar)
        {
            return;
        }

        _handling = true;
        try
        {
            WindowState = WindowState.Minimized;
        }
        finally
        {
            _handling = false;
        }

        Dispatcher.BeginInvoke(CommandSetsWindow.Present);
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            if (WindowState != WindowState.Minimized)
            {
                WindowState = WindowState.Minimized;
            }

            return;
        }

        WindowTracker.Changed -= UpdateVisibility;
        AppEvents.PreferencesChanged -= UpdateVisibility;
        _source?.RemoveHook(WndProc);
        base.OnClosing(e);
    }

    void HookWindow()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        _source?.RemoveHook(WndProc);
        _source = HwndSource.FromHwnd(hwnd);
        _source?.AddHook(WndProc);
    }

    IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmSysCommand && ShowInTaskbar && (wParam.ToInt32() & 0xFFF0) == ScRestore)
        {
            handled = true;
            ShowWindow(hwnd, SwShowMinNoActive);
            Dispatcher.BeginInvoke(CommandSetsWindow.Present);
        }

        return IntPtr.Zero;
    }

    void UpdateVisibility()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(UpdateVisibility);
            return;
        }

        var show = !DockIconSettings.IsHidden && !WindowTracker.HasContentWindows;
        if (ShowInTaskbar != show)
        {
            ShowInTaskbar = show;
        }

        if (show && WindowState != WindowState.Minimized)
        {
            _handling = true;
            try
            {
                WindowState = WindowState.Minimized;
            }
            finally
            {
                _handling = false;
            }
        }

        ApplyTaskbarStyle();
    }

    void ApplyTaskbarStyle()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        var style = GetExStyle(hwnd).ToInt64();
        if (ShowInTaskbar)
        {
            style = (style & ~WsExToolWindow) | WsExAppWindow;
        }
        else
        {
            style = (style & ~WsExAppWindow) | WsExToolWindow;
        }

        SetExStyle(hwnd, new IntPtr(style));
        SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
        if (ShowInTaskbar)
        {
            ShowWindow(hwnd, SwShowMinNoActive);
        }
    }

    static IntPtr GetExStyle(IntPtr hwnd)
    {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hwnd, GwlExStyle) : new IntPtr(GetWindowLong32(hwnd, GwlExStyle));
    }

    static void SetExStyle(IntPtr hwnd, IntPtr style)
    {
        if (IntPtr.Size == 8)
        {
            SetWindowLongPtr64(hwnd, GwlExStyle, style);
        }
        else
        {
            SetWindowLong32(hwnd, GwlExStyle, style.ToInt32());
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
    static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
