using System.Reflection;

namespace Commando;

public static class AppInfo
{
    public static readonly Uri CompanyUrl = new("https://manticore.nz");
    public static readonly Uri PurchaseUrl = new("https://manticore.nz/commando/purchase");
    public static readonly Uri PrivacyUrl = new("https://manticore.nz/commando/privacy");
    public static readonly Uri TermsUrl = new("https://manticore.nz/commando/terms");
    public static readonly Uri NewsUrl = new("https://manticore.nz/news");

    public static Uri LicenseCheckUrl => Licensing.LicenseEndpoints.CheckUrl;
    public static Uri LicenseReportUrl => Licensing.LicenseEndpoints.ReportUrl;

    public static string Name => "Commando";

    public static string ShortVersion
    {
        get
        {
            var informational = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (string.IsNullOrWhiteSpace(informational))
            {
                return "1.0.0";
            }

            var plus = informational.IndexOf('+');
            return plus >= 0 ? informational[..plus] : informational;
        }
    }

    public static string Version
    {
        get
        {
            var assemblyVersion = Assembly.GetExecutingAssembly().GetName().Version;
            var build = assemblyVersion?.Revision ?? 1;
            if (build < 0)
            {
                build = 1;
            }

            return $"{ShortVersion} ({build})";
        }
    }

    public static string Copyright =>
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyCopyrightAttribute>()?.Copyright
        ?? "Copyright © 2026 Jordan Trbuhovic. All rights reserved.";
}
