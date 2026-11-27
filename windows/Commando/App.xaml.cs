using System.IO;
using System.Windows;
using Commando.Licensing;
using Commando.Models;
using Commando.Storage;
using Commando.UI;
using Commando.Updates;

namespace Commando;

public partial class App : System.Windows.Application
{
    Mutex? _mutex;
    EventWaitHandle? _showEvent;
    Thread? _signalThread;
    volatile bool _stopping;
    TrayIconController? _tray;
    TaskbarAnchor? _anchor;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            try
            {
                File.WriteAllText(Path.Combine(Path.GetTempPath(), "commando-startup-error.txt"), args.Exception.ToString());
            }
            catch
            {
                // The dialog below still reports the failure.
            }

            MessageBox.Show(args.Exception.Message, "Commando", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };

        try
        {
            _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\com.manticoresw.commando.show");
            _mutex = new Mutex(true, @"Local\com.manticoresw.commando", out var createdNew);
            if (!createdNew)
            {
                _showEvent.Set();
                Shutdown();
                return;
            }

            _signalThread = new Thread(() =>
            {
                while (!_stopping && _showEvent != null)
                {
                    if (_showEvent.WaitOne(500))
                    {
                        Dispatcher.BeginInvoke(CommandSetsWindow.Present);
                    }
                }
            })
            {
                IsBackground = true,
                Name = "Commando.Show",
            };
            _signalThread.Start();

            CommandStore.Start();
            ExampleCommandSet.InstallIfNeeded();
            LicenseStatus.HydrateFromStorage();
            LicenseStatus.RunStartupIntegrityCheck();
            UpdateChecker.CheckForUpdateIfNeeded();

            _anchor = new TaskbarAnchor();
            _anchor.Show();
            _tray = new TrayIconController();
            AppEvents.CommandSetsChanged += _tray.RebuildMenu;
            AppEvents.PreferencesChanged += _tray.ApplyIcon;
            AppEvents.PreferencesChanged += _tray.RebuildMenu;
            AppEvents.LicenseChanged += _tray.LicenseChanged;

            LicenseStatus.RefreshRemoteStatus();
            LicenseStatus.StartPeriodicRemoteRefreshIfNeeded();
        }
        catch (Exception ex)
        {
            try
            {
                File.WriteAllText(Path.Combine(Path.GetTempPath(), "commando-startup-error.txt"), ex.ToString());
            }
            catch
            {
                // Still show the message box.
            }

            MessageBox.Show(ex.ToString(), "Commando", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _stopping = true;
        try
        {
            _showEvent?.Set();
        }
        catch
        {
            // The process is already leaving.
        }

        _tray?.Dispose();
        if (_anchor != null)
        {
            _anchor.AllowClose();
            _anchor.Close();
        }

        base.OnExit(e);
    }
}
