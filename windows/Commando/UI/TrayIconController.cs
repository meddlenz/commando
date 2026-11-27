using System.Windows.Forms;
using Commando.Execution;
using Commando.Licensing;
using Commando.Preferences;
using Commando.Storage;
using Forms = System.Windows.Forms;

namespace Commando.UI;

sealed class TrayIconController : IDisposable
{
    readonly NotifyIcon _icon;
    readonly Forms.ContextMenuStrip _menu;
    bool _revocationAlertShown;

    public TrayIconController()
    {
        _menu = new Forms.ContextMenuStrip();
        _icon = new NotifyIcon
        {
            Visible = true,
            Text = "Commando",
            ContextMenuStrip = _menu,
        };
        _icon.MouseUp += (_, args) =>
        {
            if (args.Button == MouseButtons.Left)
            {
                typeof(NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                    ?.Invoke(_icon, null);
            }
        };
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        ApplyIcon();
        RebuildMenu();
    }

    public void ApplyIcon()
    {
        var previous = _icon.Icon;
        _icon.Icon = IconResources.TrayIcon(MenuBarIconSettings.Selected);
        previous?.Dispose();
    }

    public void RebuildMenu()
    {
        _menu.Items.Clear();
        var commandSets = CommandStore.CommandSets;
        if (commandSets.Count == 0)
        {
            _menu.Items.Add(new Forms.ToolStripMenuItem("No command sets configured") { Enabled = false });
        }
        else
        {
            foreach (var commandSet in commandSets)
            {
                var title = string.IsNullOrEmpty(commandSet.Name) ? commandSet.MenuSubtitle : commandSet.Name;
                var item = new Forms.ToolStripMenuItem(title, null, (_, _) => Run(commandSet.Id))
                {
                    Image = PlayImage(),
                };
                _menu.Items.Add(item);
            }
        }

        _menu.Items.Add(new Forms.ToolStripSeparator());
        _menu.Items.Add(new Forms.ToolStripMenuItem("Command Sets", null, (_, _) => CommandSetsWindow.Present()));
        var settings = new Forms.ToolStripMenuItem("Settings", null, (_, _) => SettingsWindow.Present());
        _menu.Items.Add(settings);
        _menu.Items.Add(new Forms.ToolStripSeparator());

        if (LicenseStatus.IsRevoked)
        {
            _menu.Items.Add(new Forms.ToolStripMenuItem("License revoked") { Enabled = false });
        }

        if (!LicenseStatus.IsUnlocked)
        {
            _menu.Items.Add(new Forms.ToolStripMenuItem("Purchase Commando", null, (_, _) => Browser.Open(AppInfo.PurchaseUrl)));
            _menu.Items.Add(new Forms.ToolStripMenuItem("Enter license key", null, (_, _) => RegistrationWindow.Present()));
        }

        _menu.Items.Add(new Forms.ToolStripMenuItem("About", null, (_, _) => AboutWindow.Present()));
        _menu.Items.Add(new Forms.ToolStripMenuItem("Quit", null, (_, _) => System.Windows.Application.Current.Shutdown()));
    }

    public void LicenseChanged()
    {
        RebuildMenu();
        PresentRevocationAlertIfNeeded();
    }

    public void Dispose()
    {
        Microsoft.Win32.SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _icon.Visible = false;
        _icon.Dispose();
        _menu.Dispose();
    }

    void OnUserPreferenceChanged(object? sender, Microsoft.Win32.UserPreferenceChangedEventArgs e)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher == null)
        {
            return;
        }

        dispatcher.BeginInvoke(ApplyIcon);
    }

    void PresentRevocationAlertIfNeeded()
    {
        if (!LicenseStatus.IsRevoked)
        {
            _revocationAlertShown = false;
            return;
        }

        if (_revocationAlertShown)
        {
            return;
        }

        _revocationAlertShown = true;
        ChoiceDialog.Show(
            null,
            "License revoked",
            RegistrationException.MessageFor(RegistrationErrorKind.Revoked),
            "Ok");
    }

    static void Run(Guid id)
    {
        var commandSet = CommandStore.CommandSets.FirstOrDefault(set => set.Id == id);
        if (commandSet == null)
        {
            return;
        }

        try
        {
            CommandExecutor.Run(commandSet);
        }
        catch (Exception ex)
        {
            ChoiceDialog.Show(null, "Unable to run command", ex.Message, "Ok");
        }
    }

    static System.Drawing.Image PlayImage()
    {
        var bitmap = new System.Drawing.Bitmap(16, 16);
        using var graphics = System.Drawing.Graphics.FromImage(bitmap);
        graphics.Clear(System.Drawing.Color.Transparent);
        graphics.FillPolygon(
            System.Drawing.Brushes.Black,
            new[]
            {
                new System.Drawing.Point(4, 3),
                new System.Drawing.Point(13, 8),
                new System.Drawing.Point(4, 13),
            });
        return bitmap;
    }
}
