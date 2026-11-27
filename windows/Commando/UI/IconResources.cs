using System.Drawing;
using System.IO;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Commando.Preferences;
using Microsoft.Win32;

namespace Commando.UI;

static class IconResources
{
    public static ImageSource? AppIcon() => LoadImage("AppIcon");

    public static ImageSource? Preview(MenuBarIconSettings.Option option) =>
        LoadImage(MenuBarIconSettings.AssetName(option));

    public static Icon TrayIcon(MenuBarIconSettings.Option option)
    {
        var template = MenuBarIconSettings.UsesTemplateRendering(option);
        using var stream = OpenAsset(MenuBarIconSettings.AssetName(option));
        if (stream == null)
        {
            return FallbackIcon();
        }

        using var source = new Bitmap(stream);
        var tint = template ? (IsLightTheme() ? System.Drawing.Color.Black : System.Drawing.Color.White) : (System.Drawing.Color?)null;
        using var scaled = Scale(source, 32, tint);
        return ToIcon(scaled);
    }

    public static Icon FallbackIcon()
    {
        using var bitmap = new Bitmap(32, 32, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(System.Drawing.Color.Transparent);
        graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using var font = new Font(System.Drawing.FontFamily.GenericMonospace, 10, System.Drawing.FontStyle.Bold);
        graphics.DrawString(">_", font, System.Drawing.Brushes.Black, 1, 6);
        return ToIcon(bitmap);
    }

    static ImageSource? LoadImage(string name)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri("pack://application:,,,/Assets/" + name + ".png", UriKind.Absolute);
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    static Stream? OpenAsset(string name)
    {
        try
        {
            var info = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/" + name + ".png", UriKind.Absolute));
            return info?.Stream;
        }
        catch
        {
            return null;
        }
    }

    static Bitmap Scale(Bitmap source, int size, System.Drawing.Color? tint)
    {
        var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.DrawImage(source, new Rectangle(0, 0, size, size));
        if (tint == null)
        {
            return bitmap;
        }

        var color = tint.Value;
        for (var y = 0; y < bitmap.Height; y++)
        {
            for (var x = 0; x < bitmap.Width; x++)
            {
                var pixel = bitmap.GetPixel(x, y);
                if (pixel.A == 0)
                {
                    continue;
                }

                bitmap.SetPixel(x, y, System.Drawing.Color.FromArgb(pixel.A, color));
            }
        }

        return bitmap;
    }

    static Icon ToIcon(Bitmap bitmap)
    {
        var handle = bitmap.GetHicon();
        try
        {
            using var icon = Icon.FromHandle(handle);
            return (Icon)icon.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    public static bool IsLightTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
        }
        catch
        {
            return true;
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool DestroyIcon(IntPtr handle);
}
