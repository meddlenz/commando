namespace Commando.Preferences;

public static class MenuBarIconSettings
{
    public enum Option
    {
        BadgeColoured,
        Badge,
        Dogtags,
        Helmet,
    }

    public static Option Selected
    {
        get
        {
            var raw = Storage.Preferences.MenuBarIcon;
            return raw switch
            {
                "badge" => Option.Badge,
                "dogtags" => Option.Dogtags,
                "helmet" => Option.Helmet,
                "badgeColoured" => Option.BadgeColoured,
                _ => Option.BadgeColoured,
            };
        }
        set
        {
            Storage.Preferences.MenuBarIcon = value switch
            {
                Option.Badge => "badge",
                Option.Dogtags => "dogtags",
                Option.Helmet => "helmet",
                _ => "badgeColoured",
            };
            AppEvents.RaisePreferencesChanged();
        }
    }

    public static string Title(Option option) => option switch
    {
        Option.Badge => "Badge",
        Option.Dogtags => "Dog Tags",
        Option.Helmet => "Helmet",
        _ => "Badge (Coloured)",
    };

    public static string AssetName(Option option) => option switch
    {
        Option.Badge => "MenuBarIconBadge",
        Option.Dogtags => "MenuBarIconDogtags",
        Option.Helmet => "MenuBarIconHelmet",
        _ => "MenuBarIconBadgeColoured",
    };

    public static bool UsesTemplateRendering(Option option) => option != Option.BadgeColoured;

    public static IReadOnlyList<Option> All { get; } = new[]
    {
        Option.BadgeColoured,
        Option.Badge,
        Option.Dogtags,
        Option.Helmet,
    };
}
